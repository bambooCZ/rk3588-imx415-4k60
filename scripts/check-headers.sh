#!/bin/sh
# Refuse to build against headers whose configuration drifted from the running
# kernel's. Kbuild re-evaluates the config with the LOCAL toolchain: headers set up
# without pahole silently lose DEBUG_INFO_BTF(_MODULES), which changes struct module,
# and the module then loads but can never be unloaded ([permanent]).
# Only the toolchain's own identity and capability probes may differ.
#   check-headers.sh KVER KDIR
KVER=$1
KDIR=$2
REF=/boot/config-$KVER
CUR=$KDIR/include/config/auto.conf
TOOLCHAIN='^CONFIG_((CC|AS|LD)_IS_[A-Z]+|(CC|AS|LD|GCC|CLANG|LLD|PAHOLE|RUSTC)_VERSION(_TEXT)?|CC_CAN_LINK(_STATIC)?|CC_HAS_[A-Z0-9_]+|PAHOLE_HAS_[A-Z0-9_]+|CC_HAVE_[A-Z0-9_]+|AS_HAS_[A-Z0-9_]+|TOOLS_SUPPORT_[A-Z0-9_]+|GCC_ASM_GOTO_OUTPUT_WORKAROUND|ARCH_SUPPORTS_SHADOW_CALL_STACK)='

[ -f "$CUR" ] || { echo "check-headers: $CUR missing: the headers in $KDIR are not prepared for module builds" >&2; exit 1; }
[ -f "$REF" ] || { echo "check-headers: $REF not found, config comparison skipped (make check still compares struct module)"; exit 0; }

# auto.conf keeps string values unquoted, the kernel's config quotes them.
enabled() { grep -E '^CONFIG_' "$1" | grep -Ev "$TOOLCHAIN" | sed 's/="\(.*\)"$/=\1/' | sort; }
a=$(mktemp); b=$(mktemp)
trap 'rm -f "$a" "$b"' EXIT
enabled "$REF" > "$a"
enabled "$CUR" > "$b"
if ! cmp -s "$a" "$b"; then
    echo "check-headers: the headers' configuration differs from the running kernel's ($REF):" >&2
    diff "$a" "$b" | grep -E '^[<>]' | head -20 >&2
    if grep -q '^CONFIG_DEBUG_INFO_BTF=y' "$REF" && ! grep -q '^CONFIG_DEBUG_INFO_BTF=y' "$CUR"; then
        echo "The headers were set up without pahole. Fix:" >&2
        echo "  sudo apt install dwarves && sudo apt install --reinstall linux-headers-<your kernel flavour>" >&2
        echo "(Armbian vendor kernel: linux-headers-vendor-rk35xx)" >&2
    fi
    exit 1
fi
echo "check-headers: configuration matches $REF - ok"
