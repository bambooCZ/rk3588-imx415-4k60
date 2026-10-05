# IMX415 at 4K@60 on RK3588 (Rockchip BSP kernel)

Radxa Camera 4K (Sony IMX415) at a real 4K@60 on the ROCK 5B — Armbian vendor kernel,
no kernel rebuild.

## Quick start (Armbian)

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
[build from source](#build-from-source).

### Try it with GStreamer

Installing rkaiq and GStreamer with Rockchip's MPP plugin on Armbian is out of scope
here. Tested with:

- [rkaiq 2026_09_08](https://github.com/JeffyCN/mirrors/archive/refs/tags/rkaiq-2026_09_08.zip)
- [the IQ file from Radxa OS](https://gist.github.com/bambooCZ/8053179a154b463e2d93d5a02252c42b),
  in `/etc/iqfiles/` under its own name:

  ```sh
  sudo wget -P /etc/iqfiles "https://gist.githubusercontent.com/bambooCZ/8053179a154b463e2d93d5a02252c42b/raw/imx415_RADXA-CAMERA-4K_DEFAULT.json"
  ```

- [gstreamer-rockchip](https://github.com/JeffyCN/mirrors/tree/gstreamer-rockchip) with
  [PR#84](https://github.com/JeffyCN/mirrors/pull/84) (DMABuf caps on the encoders) and
  [PR#85](https://github.com/JeffyCN/mirrors/pull/85) (enough capture buffers)

```sh
# the ISP main path node, e.g. /dev/video11
v4l2-ctl --list-devices | grep -A1 rkisp_mainpath

gst-launch-1.0 -e \
  v4l2src device=/dev/video11 io-mode=dmabuf \
  ! video/x-raw,format=UYVY,width=3840,height=2160,framerate=60/1 \
  ! queue max-size-buffers=2 max-size-bytes=0 max-size-time=0 \
  ! mpph265enc rc-mode=cbr bps=35000000 gop=60 max-pending=4 \
  ! h265parse ! matroskamux ! filesink location=4k60.mkv
```

Stop it with Ctrl+C. For 1080p60 set `width=1920,height=1080` and a lower `bps`.

## 30 or 60 fps

The overlay sets the rate; change it in `/boot/armbianEnv.txt` and reboot:

- **60 fps:** `user_overlays=rock-5b-radxa-camera-4k-60fps`, no `rock-5b-radxa-camera-4k`
  in `overlays=`;
- **30 fps** (stock driver): `overlays=rock-5b-radxa-camera-4k`, no
  `rock-5b-radxa-camera-4k-60fps` in `user_overlays=`.

Never both. Set your pipeline's `framerate` to the rate the overlay gives: the ISP
delivers the sensor's rate whatever the caps ask for.

## Status

Verified on a ROCK 5B with Armbian's `vendor-rk35xx` 6.1.115 kernel and the setup
above:

- ISP: 60.00 fps at 3864×2192 and 1920×1080, 0 CSI-2 errors, no frame lost;
- the pipeline above, 10 s each at 4K60 (35 Mbit/s) and 1080p60 (12 Mbit/s): 600 frames,
  every timestamp 16.67 ms apart, no repeated frame;
- the DKMS package installs on Armbian 26.8.3 (trixie).

Booting with the `armbianEnv.txt` settings on an Armbian image is not confirmed yet —
reports welcome.

Radxa OS is not supported: its ROCK 5B image ships a 6.1.84 rk-6.1-rkr4.1 kernel, which
this rkr5.1 driver does not build against, and has no official route to a newer one.

## Build from source

Requirements:

- a Rockchip BSP kernel 6.1 with the vendor ISP stack (rkcif, rkisp, rkaiq) and its
  headers; the driver source is from `armbian/linux-rockchip` `rk-6.1-rkr5.1`, other
  6.1 BSP drops may need the patch refreshed;
- `build-essential bc flex bison libssl-dev libelf-dev patch device-tree-compiler kmod binutils`;
- an initramfs built by `initramfs-tools` or `mkinitcpio`.

```sh
git clone https://github.com/bambooCZ/rk3588-imx415-4k60.git
cd rk3588-imx415-4k60
make                 # builds imx415_60fps.ko, derives the overlay
make check           # vermagic, binding, struct module vs. your kernel
sudo make install    # module, overlay, initramfs
make config-hints    # the boot configuration lines for your system
```

`make install` stops if the module does not match the running kernel. A warning about
BTF is harmless: the module works but cannot be unloaded; to fix it, install `dwarves`,
reinstall the kernel headers package and rebuild.

On extlinux, put `rock-5b-radxa-camera-4k-60fps.dtbo` in `fdtoverlays` in place of
`rock-5b-radxa-camera-4k.dtbo`, and `initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev`
in `append`.

Variables: `KVER` (default `uname -r`), `KDIR` (default `/lib/modules/$KVER/build`),
`DTBO_SRC` (the stock overlay; for another board, its own IMX415 overlay).
`make deb` builds the DKMS package. `sudo make uninstall` removes module, overlay and
initramfs entry.

Verify after reboot:

```sh
lsmod | grep imx415_60fps
v4l2-ctl -d /dev/video11 --set-fmt-video=width=3840,height=2160,pixelformat=UYVY \
         --stream-mmap --stream-count=600    # ~60.00 fps
cat /proc/rkisp0-vir0                        # frameloss stays put while streaming
grep mipi-csi2 /proc/interrupts              # CSI-2 errors: stays put
```

## How it works

The Rockchip vendor IMX415 driver gets one more mode, first in the 4-lane table:
3864×2192, 10-bit, linear, 60 fps, 4 lanes at 1485 Mbps. Its registers are the 4K@30
table's with:

| Register | 4K@30 | 4K@60 |
| :-- | :-- | :-- |
| HMAX `0x3028` / VMAX `0x3024` | `0x044C` / `0x08CA` | `0x0210` / `0x0928` (7.111 µs × 2344 lines = 16.67 ms) |
| SYS_MODE `0x3033` / INCKSEL3 `0x3118` | `0x05` / `0xC0` | `0x08` / `0xA0` |
| INCKSEL6 `0x400C` / INCKSEL7 `0x4074` | `0x00` / `0x01` | `0x01` / `0x00` |
| D-PHY timings `0x4018`–`0x4028` | 891M values | 1485M values (from the driver's HDR tables) |

Three things make it work on RK3588:

1. **The driver reports a 760 MHz link (1520 Mbps) while the sensor sends 1485 Mbps.**
   The RK3588 D-PHY receiver calibrates only above 1500 Mbps; uncalibrated at 1485 it
   fails the CRC of nearly every line (64 000–132 000 CSI-2 errors/s), calibrated it has
   none.
2. **152 lines (1.08 ms) of vertical blanking.** rkcif needs ≥ 1 ms with the ISP
   online; with less, the ISP repeats timestamps.
3. **A module beside the built-in driver.** The stock driver is built in, so this one
   is `imx415-60fps`, matching only `pitwall,imx415-60fps`; the overlay is the stock one
   with that `compatible`. `initcall_blacklist` keeps rkcif and rkisp from dropping the
   sensor before modules load, and the initramfs loads the module before rkcif's 5 s
   deadline.

## Known issue: `ksoftirqd/0` tasklet storm

On Armbian's 6.1.115 kernel, after the camera stream has been stopped and started since
boot, a lighting change can leave `ksoftirqd/0` spinning until reboot — one core lost.
A rkisp bug, not this driver's; fixed upstream in rk-6.1-rkr7.2 (`04989b3cba01`).

## Diagnostics

Module parameters in `/sys/module/imx415_60fps/parameters/`: `force_mode` pins the mode
table index (-1 = normal); `reg_override` takes `(reg << 8) | val` writes applied at
stream start.

## License

GPL-2.0, like the Rockchip `imx415.c` and helper headers in `vendor/` (unchanged, from
`armbian/linux-rockchip` `rk-6.1-rkr5.1` @ `372ce582b94a3360a29727c3c49c88bb7509da22`).
