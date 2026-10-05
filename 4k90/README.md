# 4K90 (experiment)

The IMX415 at 3864×2192 **90 fps** on a ROCK 5B: 2376 Mbps per lane, both RK3588 ISPs
("unite"), rkaiq running. Not part of the release package.

| Stage | 4K90 | Measured |
| :-- | :-- | :-- |
| MIPI link, 2376 Mbps (1188 MHz) | ✅ | 0 CSI-2 errors: dark, white and normal scenes |
| Sensor | ✅ | 90.03 fps, valid image |
| One ISP | ❌ | no frames out (`CIF_ISP_PIC_SIZE_ERROR`) |
| Both ISPs (unite) | ✅ | 90.03 fps, 0 frames lost, no seam, rkaiq AE/AWB working |
| H.265 encode (RKMPP), 4K | ❌ | ~84 fps max, the ISP drops the rest |
| H.265 encode, 2560×1440 (ISP-scaled) | ✅ | 1800 frames in 20 s, 90.03 fps, every timestamp 11.1 ms apart, no repeated frame, 0 lost |

Tested on Armbian's `vendor-rk35xx` 6.1.115 kernel, the stock Radxa Camera 4K and its
150 mm cable, rkaiq 2026_09_08.

## Try it (Armbian, build from source)

1. Remove the package if it is installed: `sudo apt remove imx415-60fps-dkms`.
2. Build the driver with this patch and install it:

   ```sh
   cp 4k90/imx415-4k90.patch imx415-60fps.patch
   make && make check && sudo make install
   ```

   The patched driver defaults to 4K90, which a single ISP cannot take: do steps 3–4
   before rebooting.

3. Install the unite overlay:

   ```sh
   dtc -@ -I dts -O dtb -o rock-5b-radxa-camera-4k-unite.dtbo 4k90/rock-5b-radxa-camera-4k-unite.dts
   sudo cp rock-5b-radxa-camera-4k-unite.dtbo /boot/overlay-user/
   ```

4. In `/boot/armbianEnv.txt`, load it **after** the 60fps overlay:

   ```
   user_overlays=rock-5b-radxa-camera-4k-60fps rock-5b-radxa-camera-4k-unite
   ```

   with `extraargs=…initcall_blacklist=rkcif_clr_unready_dev,rkisp_clr_unready_dev` as
   in the [main README](../README.md#quick-start-armbian).

5. Reboot. `/proc/rkisp-unite0` exists when unite is active.

```sh
gst-launch-1.0 -e \
  v4l2src device=/dev/video11 io-mode=dmabuf \
  ! video/x-raw,format=UYVY,width=2560,height=1440,framerate=90/1 \
  ! queue max-size-buffers=2 max-size-bytes=0 max-size-time=0 \
  ! mpph265enc rc-mode=cbr bps=25000000 gop=90 max-pending=4 \
  ! h265parse ! matroskamux ! filesink location=1440p90.mkv
```

Back to 4K60: drop `rock-5b-radxa-camera-4k-unite` from `user_overlays`, reinstall the
release package, reboot.

## What it takes

### 1. The sensor at 2376 Mbps

The patch puts a 4K90 mode first in the 4-lane table (rkaiq picks the first mode of a
size). Registers, against the 4K60 mode:

| Register | 4K60 (1485 Mbps) | 4K90 (2376 Mbps) | Source |
| :-- | :-- | :-- | :-- |
| HMAX `0x3028` / VMAX `0x3024` | `0x0210` / `0x0928` | `0x0160` / `0x0927` | 4.741 µs × 2343 = 11.108 ms |
| SYS_MODE `0x3033` / INCKSEL3 `0x3118`–`0x3119` | `0x08` / `0x0A0` | `0x00` / `0x100` | mainline imx415.c, 2376M at 37.125 MHz |
| INCKSEL6 `0x400C` / INCKSEL7 `0x4074` | `0x01` / `0x00` | `0x01` / `0x00` | same |
| D-PHY timings `0x4018`–`0x4028` | 1485M values | `E7 8F 8F 7F/02 97 0F/01 97 F7 7F` | the vendor driver's 2376M 2-lane table |

The driver reports 1188 MHz: D-PHY settle `0x41`, receiver calibration on.

**HMAX `0x15E` is the floor** at 2376 Mbps: at `0x15C` and below the link stays clean
but the sensor sends every row identical (a striped image). So exact 90 fps leaves
0.72 ms of vertical blanking; rkcif warns about < 1 ms with the ISP online, harmless
with unite (no repeated timestamps in 1800 frames).

The vendor tables' 1782 Mbps settings are not clean (from ~100 to ~96 000 CSI-2
errors/s depending on the scene, whatever the receiver's settle); 2376 Mbps with mainline's clock settings
is.

### 2. Both ISPs

One ISP core runs at 702 MHz, about 3460 cycles per 4.9 µs line — fewer than the 3864
pixels in it. `rockchip,rk3588-rkisp-unite` drives both ISPs as one device: rkcif sends
the left half of each line to one ISP and the right half to the other (online,
`TOISP_UNITE`), each processes ~1940 pixels per line, the output lands in one buffer.
rkaiq detects it (`RK_AIQ_ISP_UNITE_MODE_TWO_GRID`) and splits its parameters.

[`rock-5b-radxa-camera-4k-unite.dts`](rock-5b-radxa-camera-4k-unite.dts) follows
Rockchip's own example (`rk3588s-evb1-lp4x-v10-camera.dtsi`, "dual isp process image
case"): `rkisp_unite` and its IOMMU on, `rkisp0` and its IOMMU off, `rkisp0_vir0` on
`rockchip,hw = <&rkisp_unite>`. Both ISPs are taken: no second camera.

### 3. The encoder

RKMPP H.265 tops out at ~83–87 fps at 4K, with the ISP dropping a few frames per second
throughout; `max-pending` 4, 6 or 8 makes no consistent difference. Encode a smaller ISP output instead: 1440p90 has headroom.

## Diagnostics in the patch

Module parameters in `/sys/module/imx415_60fps/parameters/`:

- `force_mode` — mode table index (rkaiq overrides it at stream start; stop rkaiq for
  link tests);
- `link_freq_idx` — report another link frequency (index into `link_freq_items`;
  950 and 1050 MHz added) to pick another D-PHY settle range;
- `reg_override` — `(reg << 8) | val` sensor writes at stream start.

Mode table: 0 = 4K90 (default), 1 = 4K60, 11 = 4K at a real 1782 Mbps, 12 = 4K90 at
HMAX `0x16E` (0.29 ms vblank).

Measured with: CSI-2 errors from the `rockchip-mipi-csi2-hw` lines in `/proc/interrupts`;
the link and sensor alone by raw capture from `stream_cif_mipi_id0` (`GB10`, Rockchip's
compact RAW10); `frameloss` in `/proc/rkisp-unite0`; files by `ffprobe` timestamps and
`ffmpeg -f framemd5`.
