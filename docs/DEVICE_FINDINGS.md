# Connected device findings

Captured from the user's Xiaomi Pad 6 on 2026-05-30.

## Android / fastboot

- Device: `pipa`
- Model: `23043RP34G`
- Android product: `pipa_id`
- Android active slot before switching: `a`
- Bootloader: unlocked
- Verified boot state: orange
- `boot_a`: `/dev/block/sde12`
- `boot_b`: `/dev/block/sde37`
- `linux`: `/dev/block/sda35`
- `userdata`: `/dev/block/sda34`
- `super`: `/dev/block/sda29`
- Fastboot-reported `linux` partition size: 108.36 GiB
- Fastboot-reported `boot_a` / `boot_b` size: 192 MiB each

## postmarketOS

- SSH host: `192.168.1.60`
- SSH user confirmed: `dev`
- OS: postmarketOS v25.06
- Kernel: `6.15.8-sm8250-pipa`
- Hostname: `xiaomi-pipa`
- Root: `/dev/mapper/sda35p2`, ext4
- Boot: `/dev/mapper/sda35p1`, ext2
- Linux partition layout: `sda35` contains nested partitions:
  - `sda35p1`: 236 MiB, `/boot`
  - `sda35p2`: 108.1 GiB, `/`

## Working hardware clues

- GPU/display: Linux DRM MSM stack exposes `card0`, `renderD128`, DSI, DP, writeback.
- GPU firmware found: `a650_zap.mbn`.
- Touchscreen: `NVTCapacitiveTouchScreen`, event6.
- Pen: `NVTCapacitivePen`, event7.
- Keyboard/touchpad cover: `Nanosic 803 keyboard`, `Nanosic 803 touchpad`.
- Audio firmware/DSP files found: `adsp.mbn`, Awinc `aw88230_2113_pipa.bin`.
- Camera nodes exist in DTS/dmesg around CAMSS and CCI camera sensor at address `0x10`.

## Install implication

The current pmOS root lives on the exact `linux` partition that Windows should
replace. Do not expose or overwrite `/dev/sda35` while booted from pmOS.

Safer install route:

1. Build a Windows disk image on the PC.
2. Convert it to Android sparse image format.
3. Boot tablet to fastboot.
4. Flash sparse image to `linux`.
5. Flash a pipa UEFI boot image to `boot_b`.
6. Set active slot `b`.

