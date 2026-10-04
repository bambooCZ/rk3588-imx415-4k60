# IMX415 at 4K@60 on RK3588 (Rockchip BSP kernel)

Radxa Camera 4K (Sony IMX415) at a real 4K@60 on the ROCK 5B — Armbian vendor kernel,
no kernel rebuild.

## Installation (Armbian)

1. Install the package:

   ```sh
   wget "https://github.com/bambooCZ/rk3588-imx415-4k60/releases/latest/download/imx415-60fps-dkms.deb"
   sudo apt update
   sudo apt install ./imx415-60fps-dkms.deb
   ```

2. Edit `/boot/armbianEnv.txt`:
   - **remove** `rock-5b-radxa-camera-4k` (the stock camera overlay) from the `overlays=`
     line, if it is there;
   - **add** `rock-5b-radxa-camera-4k-60fps` to the `user_overlays=` line
     (create the line if there is none; values are space separated);
   - **add** `initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev` to the
     `extraargs=` line (create the line if there is none).

   For example (keep your own `rootdev`, `fdtfile` and other lines as they are):

   ```
   verbosity=1
   bootlogo=false
   console=both
   extraargs=cma=256M initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev
   overlay_prefix=rockchip-rk3588
   fdtfile=rockchip/rk3588-rock-5b.dtb
   rootdev=UUID=<your root filesystem UUID>
   rootfstype=ext4
   user_overlays=rock-5b-radxa-camera-4k-60fps
   ```

3. Reboot.

Needs Armbian's `vendor-rk35xx` kernel before Armbian 26.11. Other systems:
[build it yourself](#2-steps).

## Switching between 30 and 60 fps

The overlay decides, and nothing else does. Change it in `/boot/armbianEnv.txt` and
reboot; the package can stay installed either way:

- **60 fps:** `user_overlays=rock-5b-radxa-camera-4k-60fps`, and `rock-5b-radxa-camera-4k`
  not in `overlays=`;
- **30 fps** (the stock driver): `overlays=rock-5b-radxa-camera-4k`, and
  `rock-5b-radxa-camera-4k-60fps` not in `user_overlays=`.

Never both. Your application cannot pick the rate: the ISP delivers whatever the sensor
sends, so asking GStreamer for `framerate=30/1` on the 60 fps overlay still gives
60 fps — and an encoder that budgets bits per frame from the caps then produces twice
the bitrate you set. Configure your pipeline for the rate the overlay gives.

---

The Sony IMX415 ("Radxa Camera 4K") on a Radxa ROCK 5B, **3864×2192 at a real
60 fps** — 60 distinct frames per second through rkcif → rkisp → rkaiq, no CSI-2
errors, no duplicated timestamps — on the stock Rockchip BSP ("vendor") kernel,
**without rebuilding the kernel**. 1080p60 comes out of the same mode via the ISP's
scaler.

What you get: the Rockchip vendor IMX415 driver with one extra 4-lane linear mode,
built as an out-of-tree module (`imx415_60fps`), plus a copy of Radxa's camera overlay
that binds the sensor to it instead of the built-in driver.

> **Why this exists.** "IMX415 can't do 60 fps on RK3588" is the usual answer on the
> forums. The sensor can, the D-PHY can, the ISP can and MPP encodes 4K well past 60.
> What stood in the way are three undocumented software details, explained in
> [Why it works](#why-it-works) — each one alone makes 60 fps look impossible.

## Status

Verified on a ROCK 5B with the Radxa Camera 4K, Armbian's `vendor-rk35xx` kernel
**6.1.115** (built from `armbian/linux-rockchip` `rk-6.1-rkr5.1`), rkaiq with Radxa's
`imx415_RADXA-CAMERA-4K_DEFAULT.json`:

- ISP output 60.00 fps at 3864×2192 and at 1920×1080 (ISP-scaled), 0 CSI-2 errors,
  no frame missing from the sequence, CPU0 softirq ≤ 1 %;
- end to end with a GStreamer pipeline (`v4l2src` → GPU/RGA overlay → `mpph265enc`):
  **4K60 H.265 at 35 Mbit/s** with 0 ISP frames lost in 40 s and both rkvenc cores in
  use, **1080p60 at 12 Mbit/s** with 0 lost, RTSP at 60.0 fps with no repeated stamps.

The machine that runs it uses Arch Linux ARM with that Armbian kernel repackaged and
extlinux. The DKMS package installs on Armbian 26.8.3 (trixie, `vendor-rk35xx`
6.1.115): module built and in the initramfs, overlay in `/boot/overlay-user`. Booting
with the `armbianEnv.txt` settings on an Armbian image is not confirmed yet — reports
welcome.

## 1. Requirements

- **RK3588 board with the camera on Radxa's ROCK 5B connector.** The overlay is
  derived from `rock-5b-radxa-camera-4k.dtbo`; for another board use its own IMX415
  overlay as `DTBO_SRC` (the node path must be `/fragment@0/__overlay__/imx415@1a`,
  `make` checks).
- **Rockchip BSP kernel 6.1 with the vendor ISP stack** (rkcif, rkisp, rkaiq), e.g.
  Armbian `vendor-rk35xx` 6.1.115. The vendored driver source is from
  `armbian/linux-rockchip` `rk-6.1-rkr5.1` @ `372ce582`; other 6.1 BSP drops may need
  the patch refreshed against their own `drivers/media/i2c/imx415.c`. Mainline Linux
  has its own imx415 driver and ISP stack — this is not for it.
- **Kernel headers of exactly the running kernel**, prepared for module builds
  (Armbian: `linux-headers-vendor-rk35xx` from apt; its postinst builds the host tools).
- **Build tools:** `gcc make bc flex bison libssl-dev libelf-dev`, plus `patch`,
  `device-tree-compiler` (`fdtget`/`fdtput`), `kmod` (`modinfo`, `depmod`), `binutils`
  (`objdump`). Debian/Armbian:
  `sudo apt install build-essential bc flex bison libssl-dev libelf-dev patch device-tree-compiler kmod binutils`
  `make` compares the headers' config with `/boot/config-<kernel>` and refuses on a
  real difference.
- **rkaiq** (Rockchip's 3A server, `rkaiq_3A_server`) with the IQ file
  `imx415_RADXA-CAMERA-4K_DEFAULT.json` (Radxa's `rockchip-iqfiles`). Sensor, module and
  lens names are unchanged, so it is found as before. Without rkaiq you get a raw,
  unbalanced picture — at 60 fps.
- An initramfs built by `initramfs-tools` or `mkinitcpio` (see step 3 for why).

### Not supported: Radxa OS

Radxa OS for the ROCK 5B (rsdk r6, 2026) ships a hopelessly old vendor kernel,
**6.1.84 from rk-6.1-rkr4.1** (`linux-image-6.1.84-8-rk2410`), and there is no official
way to a newer one: Radxa builds a 6.1.115 rk-6.1-rkr5.1 kernel (`rk2501`, from
`radxa/kernel` `linux-6.1-stan-rkr5.1`) but publishes it only to the *test* apt suites
of other SoCs (RK3399, RK3308), not to `rk3588-bookworm`. The rkr5.1 driver here does
not compile against rkr4.1 (its `rk-camera-module.h` lacks `RKMODULE_GET_EXP_INFO`),
so Radxa OS is not supported. It builds fine against `rk2501` if you install that by
hand — you are on your own there.

## 2. Steps

### Armbian: the DKMS package

For Armbian's `vendor-rk35xx` kernels before Armbian 26.11 (i.e. before the
rk-6.1-rkr7.2 kernel), a `.deb` from the
[releases](https://github.com/bambooCZ/rk3588-imx415-4k60/releases) does the build and
install below for you, and DKMS rebuilds the module for every later kernel update:

```sh
sudo apt install linux-headers-vendor-rk35xx  # if not installed yet
sudo apt install ./imx415-60fps-dkms.deb
```

It builds `imx415_60fps` for each installed kernel with headers, derives
`/boot/overlay-user/rock-5b-radxa-camera-4k-60fps.dtbo` from that kernel's stock overlay
(`imx415-60fps-overlay` redoes it by hand) and adds the module to the initramfs
(`/usr/share/initramfs-tools/modules.d/imx415-60fps`). Then do **Configure** below and
reboot. It depends on `linux-image/headers/dtb-vendor-rk35xx (<< 26.11)`, so apt holds
those kernel packages back rather than upgrading to the 6.1.172 kernel it was not made
for. `make deb` builds the same package from this tree.

**A warning about BTF** means Armbian's headers package was installed while `pahole`
(`dwarves`) was not: it then rewrites its config without BTF, `struct module` comes out
smaller, and the module works but cannot be unloaded (`[permanent]` — no `rmmod`).
Harmless for a camera driver. To get `rmmod` back: `sudo apt install dwarves`,
`sudo apt install --reinstall linux-headers-vendor-rk35xx`,
`sudo dpkg-reconfigure imx415-60fps-dkms`.

### Clone

```sh
git clone https://github.com/bambooCZ/rk3588-imx415-4k60.git
cd rk3588-imx415-4k60
```

### Build

```sh
make          # patches the vendored driver, builds imx415_60fps.ko, derives the overlay
make check    # vermagic, binding, and struct module size vs. a module of your kernel
```

`make check` must pass. If it reports a different `struct module` size, your headers
do not match the running kernel's configuration (the module would load and then be
impossible to unload); fix the headers, do not force it.

Variables: `KVER` (default `uname -r`), `KDIR` (default `/lib/modules/$KVER/build`),
`DTBO_SRC` (the stock overlay, found automatically under `/boot/dtb*`, `/boot/dtbs/*`
or `/usr/lib/linux-image-$KVER`).

### Install

```sh
sudo make install
```

- the module → `/lib/modules/$KVER/updates/imx415_60fps.ko`, then `depmod`;
- the overlay → `/boot/overlay-user/rock-5b-radxa-camera-4k-60fps.dtbo` on Armbian,
  else next to the stock overlay;
- the module into the initramfs: `/etc/initramfs-tools/modules` + `update-initramfs -u`
  (Debian/Armbian), or `/etc/mkinitcpio.conf.d/imx415-60fps.conf` + `mkinitcpio -P`
  (Arch).

### Configure (by hand — it is your boot loader)

`make config-hints` prints the lines for your system.

**Armbian**, `/boot/armbianEnv.txt`:

```
user_overlays=rock-5b-radxa-camera-4k-60fps
extraargs=initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev
```

and **remove** the stock camera overlay (`radxa-camera-4k` / `rock-5b-radxa-camera-4k`)
from `overlays=` — never both, they claim the same nodes. Append to existing
`user_overlays=` / `extraargs=` values rather than replacing them.

**extlinux**, `/boot/extlinux/extlinux.conf`: in `fdtoverlays`, the
`rock-5b-radxa-camera-4k-60fps.dtbo` **instead of** `rock-5b-radxa-camera-4k.dtbo`;
in `append`, `initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev`.

### Pray (reboot) and verify

```sh
sudo reboot
lsmod | grep imx415_60fps                    # loaded
dmesg | grep -i imx415-60fps                 # probed on 3-001a
v4l2-ctl --list-devices                      # find rkisp_mainpath, e.g. /dev/video11
v4l2-ctl -d /dev/video11 --set-fmt-video=width=3840,height=2160,pixelformat=NV12 \
         --stream-mmap --stream-count=600    # prints ~60.00 fps
cat /proc/rkisp0-vir0                        # frameloss must not grow while streaming
grep mipi-csi2 /proc/interrupts             # CSI-2 error IRQs: must not grow
```

Count CSI-2 errors from `/proc/interrupts`, not from `dmesg` — the ring buffer caps
the printks.

**Rollback:** put the stock overlay back in your boot configuration; the built-in
driver takes the camera again. The `initcall_blacklist` is harmless to it and the
unbound module does nothing. `sudo make uninstall` removes the module, the overlay and
the initramfs entry.

## Why it works

### The mode

3864×2192, 10-bit, linear, 60 fps, 4 lanes at **1485 Mbps**, first in the 4-lane mode
table (so it is the default at probe and the best fit for 3864×2192). The registers are the
driver's 4K@30 linear table (891 Mbps) with:

| Register | 4K@30 | 4K@60 | Source |
| :-- | :-- | :-- | :-- |
| HMAX `0x3028` / VMAX `0x3024` | `0x044C` / `0x08CA` | `0x0210` / `0x0928` | 1H = 528 / 74.25 MHz = 7.111 µs, × 2344 = 16.67 ms; 152 lines (1.08 ms) of vblank |
| SYS_MODE `0x3033` / INCKSEL3 `0x3118` | `0x05` / `0xC0` | `0x08` / `0xA0` | the driver's own 1485M HDR tables |
| INCKSEL6 `0x400C` / INCKSEL7 `0x4074` | `0x00` / `0x01` | `0x01` / `0x00` | same; mainline's 1485 Mbps / 37.125 MHz parameters agree |
| D-PHY timings `0x4018`–`0x4028` | 891M values | 1485M values | the driver's 1485M HDR tables |

A 3864-pixel 10-bit line on 4 lanes takes 6.5 µs of the 7.1 µs line at 1485 Mbps.

### 1. The receiver must calibrate: report 1520 Mbps, send 1485

The RK3588 D-PHY receiver driver picks its settle time from the link rate the sensor
driver reports (1400–1599 Mbps → `0x2d`) and **enables receiver calibration only
above 1500 Mbps**. CSI-2 error interrupts per second, steady state:

| Sensor sends | Reported to the receiver | Errors/s |
| :-- | :-- | :-- |
| 891 Mbps (stock 4K@30) | 891 | 0 |
| 1485 Mbps | 1485 — no calibration | 64 000–132 000 |
| 1485 Mbps | **1520 — calibration on** | **0** (4K and 1080p, 60 s each) |
| 1782 Mbps (a linear 60 fps variant; the vendor's 1782M HDR modes) | 1782 | ~750, data dependent |

Without calibration the receiver fails the CRC of nearly every line while the image
still looks clean (`MIPI_CSI2 ERR1:0x1000000 (crc,vc: 0)`), costing CPU0 ~90 % softirq.
So the driver reports a **760 MHz** link (1520 Mbps): same settle range, calibration on.
That is a workaround, not something a kernel maintainer would merge; the clean fix
belongs in the D-PHY driver. `hts_def` (4324) is the true line length at the
*reported* pixel rate, so rkaiq's `pixel_rate / (hts × vts)` is still 60 fps.

### 2. At least 1 ms of vertical blanking

rkcif wants ≥ 1 ms of vblank with the ISP online (`Warning: vblank need >= 1000us`).
With a shorter blank (HMAX `0x0226` / VMAX `0x08CA`: 0.43 ms) the ISP gave ~5 % of
buffers the previous frame's timestamp — equal PTS, then a 33 ms jump. `v4l2src`
uses the driver's stamps, so downstream sees "60 fps" with half the frames repeated.
Hence the short line (HMAX `0x0210`) and the long frame (VMAX `0x0928`): 1.08 ms of
blanking, no duplicated stamp in 1800 frames.

### 3. Replacing a built-in driver, and loading it in time

The BSP kernel has the stock driver **built in** (`CONFIG_VIDEO_IMX415=y`), so a
module can neither replace it nor share its name. This one registers as
`imx415-60fps` and matches only `pitwall,imx415-60fps`; the overlay is the stock one
with that `compatible` (and its title/description) changed by `fdtput` — nothing else
differs. Then two vendor-kernel traps:

1. `rkcif` and `rkisp` drop every sensor not registered by `late_initcall`
   (`clear unready subdev num: 1`) — before any module can load. Hence
   `initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev`.
2. `rkcif` connects to the ISP only if its graph completes within 5 s of its own probe.
   Loaded by udev from the root filesystem the module comes too late (~9 s); from the
   initramfs it loads right after `/init` (~5 s).

### What about the vendor kernels' own "4K60" modes?

Some board-vendor kernels list a 3864×2192@60 mode for the IMX415. From reading their
sources (not tested here), the ones we looked at either do not program HMAX/VMAX/
SYS_MODE for it or report a link rate that cannot carry 4K60 RAW10. Judge any mode by
`v4l2-ctl --stream-mmap` and by the buffer timestamps, not by the advertised rate.

## 90 fps?

The sensor and the D-PHY (2.5 Gbps/lane) could in theory. At 90 fps a frame lasts
11.1 ms; keeping the 1.08 ms blank leaves ~10 ms to read out the frame, ~2.3 Gbps per
lane — right under the D-PHY limit, past the 1782 Mbps where this board already saw
CRC errors, and nothing a 60 Hz display or YouTube would show. Not attempted; if you
do, the three points above are where to start.

## Known issue on this kernel: `ksoftirqd/0` tasklet storm

Not caused by this driver, but you will meet it with any camera on Armbian's 6.1.115
(rk-6.1-rkr5.1): rkisp enables its LSC tasklet once per stream and disables it twice
per stop, so after any ISP stop+start since boot, the next lens-shading update (a
lighting change) leaves `ksoftirqd/0` spinning on ~4 M tasklets/s until reboot — one
core lost. Fixed upstream by Rockchip in `04989b3cba01` ("media: rockchip: isp: fix
lsc tasklet count for isp3.0", rk-6.1-rkr7.2). Reboot after restarting the camera
pipeline if you need that core.

## Diagnostics

Two module parameters, writable at runtime (`/sys/module/imx415_60fps/parameters/`):
`force_mode` pins the mode table index at probe and on every `set_fmt` (-1 = normal);
`reg_override` takes `(reg << 8) | val` writes applied at stream start.

## License

GPL-2.0, like the kernel driver it is derived from (Rockchip's `imx415.c` and its
helper headers in `vendor/`, unchanged, from `armbian/linux-rockchip` `rk-6.1-rkr5.1`
@ `372ce582b94a3360a29727c3c49c88bb7509da22`).
