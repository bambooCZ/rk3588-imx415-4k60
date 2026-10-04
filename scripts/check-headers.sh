#!/bin/sh
# Refuse to build against headers whose configuration drifted from the running
# kernel's - except for BTF, which only costs rmmod.
#
# Kbuild re-evaluates the config with the LOCAL toolchain, so only the toolchain's own
# identity and capability probes may differ. One drift is tolerated: headers set up
# without pahole lose DEBUG_INFO_BTF(_MODULES) (Armbian's headers package rewrites its
# config on install). That shrinks struct module, and the kernel then cannot find the
# module's exit function: it loads and works, but is [permanent] (no rmmod).
#   check-headers.sh KVER KDIR
# Exit status: 0 = matches (or no /boot/config to compare), 3 = only BTF differs
# (tolerated, warned), 1 = anything else.
KVER=$1
KDIR=$2
REF=/boot/config-$KVER
CUR=$KDIR/include/config/auto.conf
TOOLCHAIN='^CONFIG_((CC|AS|LD)_IS_[A-Z]+|(CC|AS|LD|GCC|CLANG|LLD|PAHOLE|RUSTC)_VERSION(_TEXT)?|CC_CAN_LINK(_STATIC)?|CC_HAS_[A-Z0-9_]+|PAHOLE_HAS_[A-Z0-9_]+|CC_HAVE_[A-Z0-9_]+|AS_HAS_[A-Z0-9_]+|TOOLS_SUPPORT_[A-Z0-9_]+|GCC_ASM_GOTO_OUTPUT_WORKAROUND|ARCH_SUPPORTS_SHADOW_CALL_STACK)='
BTF='^[<>] CONFIG_(DEBUG_INFO_BTF|DEBUG_INFO_BTF_MODULES|MODULE_ALLOW_BTF_MISMATCH)='

[ -f "$CUR" ] || { echo "check-headers: $CUR missing: the headers in $KDIR are not prepared for module builds" >&2; exit 1; }
[ -f "$REF" ] || { echo "check-headers: $REF not found, config comparison skipped"; exit 0; }

# auto.conf keeps string values unquoted, the kernel's config quotes them.
enabled() { grep -E '^CONFIG_' "$1" | grep -Ev "$TOOLCHAIN" | sed 's/="\(.*\)"$/=\1/' | sort; }
a=$(mktemp); b=$(mktemp)
trap 'rm -f "$a" "$b"' EXIT
enabled "$REF" > "$a"
enabled "$CUR" > "$b"
diffs=$(diff "$a" "$b" | grep -E '^[<>]')
if [ -z "$diffs" ]; then
    echo "check-headers: configuration matches $REF - ok"
    exit 0
fi
others=$(printf '%s\n' "$diffs" | grep -Ev "$BTF")
if [ -n "$others" ]; then
    echo "check-headers: the headers' configuration differs from the running kernel's ($REF):" >&2
    printf '%s\n' "$others" | head -20 >&2
    exit 1
fi
echo "check-headers: WARNING: the headers have no BTF (set up without pahole), the kernel has."
echo "  The module will work but cannot be unloaded ([permanent]). Harmless for a camera"
echo "  driver; to get rmmod back: apt install dwarves, reinstall the headers package, rebuild."
exit 3
