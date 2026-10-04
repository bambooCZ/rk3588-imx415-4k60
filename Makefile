# IMX415 4K@60 for the Rockchip RK3588 BSP kernel: build the patched vendor driver
# as an out-of-tree module against the running kernel's headers, derive the device
# tree overlay from the stock Radxa Camera 4K overlay, and install both.
#
#   make                 build the module and the overlay
#   make check           sanity-check the module against the running kernel
#   sudo make install    install module + overlay, add the module to the initramfs
#   make config-hints    print the boot configuration lines to add by hand
#   sudo make uninstall  undo `make install` (boot configuration is yours to revert)
#   make deb             the DKMS .deb for Armbian (needs dpkg-deb)

KVER      ?= $(shell uname -r)
KDIR      ?= /lib/modules/$(KVER)/build
MODDIR    ?= /lib/modules/$(KVER)/updates

BUILD     := build
I2C       := $(BUILD)/drivers/media/i2c
KO        := $(I2C)/imx415_60fps.ko
DTBO_NAME := rock-5b-radxa-camera-4k-60fps
DTBO      := $(BUILD)/$(DTBO_NAME).dtbo
NODE      := /fragment@0/__overlay__/imx415@1a
COMPAT    := pitwall,imx415-60fps

# The stock overlay this one is derived from: the copy that ships with THIS kernel.
DTBO_SRC  ?= $(firstword $(wildcard \
	/boot/dtb-$(KVER)/rockchip/overlay/rock-5b-radxa-camera-4k.dtbo \
	/boot/dtb/rockchip/overlay/rock-5b-radxa-camera-4k.dtbo \
	/usr/lib/linux-image-$(KVER)/rockchip/overlay/rock-5b-radxa-camera-4k.dtbo \
	/boot/dtbs/*/rockchip/overlay/rock-5b-radxa-camera-4k.dtbo))

# Armbian loads `user_overlays=` from /boot/overlay-user; anything else (extlinux
# `fdtoverlays`) gets it next to the stock overlay.
ifneq ($(wildcard /boot/armbianEnv.txt),)
OVERLAY_DIR ?= /boot/overlay-user
else
OVERLAY_DIR ?= $(patsubst %/,%,$(dir $(DTBO_SRC)))
endif

.PHONY: all prepare module overlay check install uninstall config-hints clean deb

all: module overlay

module: $(KO)
overlay: $(DTBO)

# The vendor driver keeps its in-tree layout: it includes
# "../platform/rockchip/isp/rkisp_tb_helper.h".
$(I2C)/imx415_60fps.c: vendor/drivers/media/i2c/imx415.c imx415-60fps.patch
	rm -rf $(BUILD)/drivers
	mkdir -p $(BUILD)
	cp -r vendor/drivers $(BUILD)/
	cd $(I2C) && patch -Np1 --no-backup-if-mismatch -i $(CURDIR)/imx415-60fps.patch
	mv $(I2C)/imx415.c $@
	echo 'obj-m := imx415_60fps.o' > $(I2C)/Makefile

prepare: $(I2C)/imx415_60fps.c

$(KO): $(I2C)/imx415_60fps.c
	@test -f $(KDIR)/Makefile || { echo "No kernel headers at $(KDIR): install the headers package of kernel $(KVER)"; exit 1; }
	@sh scripts/check-headers.sh $(KVER) $(KDIR)
	$(MAKE) -C $(KDIR) M=$(CURDIR)/$(I2C) modules

$(DTBO):
	@test -n "$(DTBO_SRC)" || { echo "Stock rock-5b-radxa-camera-4k.dtbo not found; pass DTBO_SRC=/path/to/it"; exit 1; }
	mkdir -p $(BUILD)
	cp $(DTBO_SRC) $(DTBO)
	@test "$$(fdtget $(DTBO) $(NODE) compatible)" = "sony,imx415" || { echo "$(DTBO_SRC): $(NODE) is not sony,imx415"; exit 1; }
	fdtput -t s $(DTBO) $(NODE) compatible $(COMPAT)
	fdtput -t s $(DTBO) /metadata title 'Enable Radxa Camera 4K (imx415-60fps driver)'
	fdtput -t s $(DTBO) /metadata description 'Enable Radxa Camera 4K, bound to the out-of-tree imx415-60fps driver instead of the built-in imx415.'
	@echo "overlay: $(DTBO) (from $(DTBO_SRC))"

# vermagic catches a different kernel; it does not catch a config drift between the
# headers and the running kernel, which shows as a different struct module size (the
# module then loads but cannot be unloaded, [permanent]). Compare with a module of the
# running kernel itself.
check: $(KO)
	@modinfo -F vermagic $(KO) | grep -q "^$(KVER) " \
		&& echo "vermagic: $(KVER) - ok" \
		|| { echo "vermagic: '$$(modinfo -F vermagic $(KO))' is not for $(KVER)"; exit 1; }
	@modinfo -F alias $(KO) | grep -q "C$(COMPAT)" && ! modinfo -F alias $(KO) | grep -q 'sony,imx415' \
		&& echo "alias: $(COMPAT) only - ok" || { echo "alias: unexpected"; exit 1; }
	@ref=$$(find /lib/modules/$(KVER)/kernel -name '*.ko*' | head -1); \
	test -n "$$ref" || { echo "struct module: no module of $(KVER) to compare with - skipped"; exit 0; }; \
	tmp=$$(mktemp); case "$$ref" in \
		*.xz) xz -dc "$$ref" > $$tmp ;; *.zst) zstd -qdc "$$ref" > $$tmp ;; *.gz) gzip -dc "$$ref" > $$tmp ;; \
		*) cp "$$ref" $$tmp ;; esac; \
	size() { objdump -h "$$1" | awk '$$2 == ".gnu.linkonce.this_module" { print $$3 }'; }; \
	a=$$(size $(KO)); b=$$(size $$tmp); rm -f $$tmp; \
	if [ "$$a" = "$$b" ]; then echo "struct module: 0x$$a, same as $$(basename $$ref) - ok"; \
	else echo "struct module: ours 0x$$a, the kernel's 0x$$b - WARNING: the module will load but cannot be unloaded (headers without BTF, see README)"; fi

install: check $(DTBO)
	@test "$$(id -u)" = 0 || { echo "install needs root: sudo make install"; exit 1; }
	install -Dm644 $(KO) $(MODDIR)/imx415_60fps.ko
	depmod -a $(KVER)
	install -Dm644 $(DTBO) $(OVERLAY_DIR)/$(DTBO_NAME).dtbo
	@echo "overlay installed: $(OVERLAY_DIR)/$(DTBO_NAME).dtbo"
	@if [ -d /etc/initramfs-tools ]; then \
		grep -qx imx415_60fps /etc/initramfs-tools/modules || echo imx415_60fps >> /etc/initramfs-tools/modules; \
		update-initramfs -u -k $(KVER); \
	elif command -v mkinitcpio >/dev/null; then \
		echo 'MODULES+=(imx415_60fps)' > /etc/mkinitcpio.conf.d/imx415-60fps.conf; \
		mkinitcpio -P; \
	else \
		echo "WARNING: no initramfs-tools or mkinitcpio: put imx415_60fps into your initramfs yourself (see README)"; \
	fi
	@echo; $(MAKE) --no-print-directory config-hints

uninstall:
	rm -f $(MODDIR)/imx415_60fps.ko
	depmod -a $(KVER)
	rm -f $(OVERLAY_DIR)/$(DTBO_NAME).dtbo
	@if [ -f /etc/initramfs-tools/modules ]; then \
		sed -i '/^imx415_60fps$$/d' /etc/initramfs-tools/modules; update-initramfs -u -k $(KVER); \
	elif [ -f /etc/mkinitcpio.conf.d/imx415-60fps.conf ]; then \
		rm -f /etc/mkinitcpio.conf.d/imx415-60fps.conf; mkinitcpio -P; \
	fi
	@echo "Now revert the boot configuration (overlay and initcall_blacklist) by hand."

config-hints:
	@echo "Boot configuration - edit by hand, then reboot:"
	@echo
	@if [ -f /boot/armbianEnv.txt ]; then \
		echo "  /boot/armbianEnv.txt:"; \
		echo "    user_overlays=$(DTBO_NAME)"; \
		echo "    extraargs=initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev"; \
		echo "  and REMOVE radxa-camera-4k / rock-5b-radxa-camera-4k from overlays= (never both)."; \
		echo "  (Append to existing user_overlays=/extraargs= values, space separated.)"; \
	else \
		echo "  /boot/extlinux/extlinux.conf (or your boot loader's equivalent):"; \
		echo "    fdtoverlays: $(OVERLAY_DIR)/$(DTBO_NAME).dtbo INSTEAD OF rock-5b-radxa-camera-4k.dtbo"; \
		echo "    append:      initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev"; \
	fi

clean:
	rm -rf $(BUILD)

DEB_VERSION := $(shell sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
DEB_ROOT    := $(BUILD)/deb
DEB_SRC     := $(DEB_ROOT)/usr/src/imx415-60fps-$(DEB_VERSION)
DEB         := $(BUILD)/imx415-60fps-dkms_$(DEB_VERSION)_all.deb

deb:
	rm -rf $(DEB_ROOT)
	install -d $(DEB_SRC) $(DEB_ROOT)/DEBIAN
	cp -r Makefile imx415-60fps.patch dkms.conf vendor scripts $(DEB_SRC)/
	install -Dm755 debian/imx415-60fps-overlay $(DEB_ROOT)/usr/sbin/imx415-60fps-overlay
	install -Dm644 debian/initramfs-modules $(DEB_ROOT)/usr/share/initramfs-tools/modules.d/imx415-60fps
	install -Dm644 LICENSE $(DEB_ROOT)/usr/share/doc/imx415-60fps-dkms/copyright
	install -Dm644 README.md $(DEB_ROOT)/usr/share/doc/imx415-60fps-dkms/README.md
	for f in control postinst prerm postrm; do \
		sed 's/@VERSION@/$(DEB_VERSION)/' debian/$$f > $(DEB_ROOT)/DEBIAN/$$f; done
	chmod 755 $(DEB_ROOT)/DEBIAN/postinst $(DEB_ROOT)/DEBIAN/prerm $(DEB_ROOT)/DEBIAN/postrm
	dpkg-deb --root-owner-group -Zxz --build $(DEB_ROOT) $(DEB)
	cp $(DEB) $(BUILD)/imx415-60fps-dkms_latest_all.deb
	@echo "deb: $(DEB) (release asset: $(BUILD)/imx415-60fps-dkms_latest_all.deb)"
