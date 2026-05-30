# Current device facts

Captured from the connected Xiaomi Pad 6 on 2026-05-30.

## Identity

- Model: `23043RP34G`
- Product/device: `pipa_id` / `pipa`
- Android release: `14`
- Hardware: `qcom`
- Graphics properties: `adreno` EGL/Vulkan

## Boot state

- Bootloader lock state from Android props: unlocked
- Verified boot state: orange
- Active Android slot from Android props: `_a`
- Fastboot product from first capture: `pipa`
- Fastboot unlocked state from first capture: `yes`

After the first fastboot capture, Windows fastboot write commands started
returning `Write to device failed (no link)`. This is a host USB/fastboot link
problem, not a destructive device change. Replug the cable or force-reboot the
tablet before the next fastboot write command.

## Partition mapping

Important by-name mappings captured from Android:

| Partition | Block device |
| --- | --- |
| `boot_a` | `/dev/block/sde12` |
| `boot_b` | `/dev/block/sde37` |
| `vendor_boot_a` | `/dev/block/sde25` |
| `vendor_boot_b` | `/dev/block/sde49` |
| `dtbo_a` | `/dev/block/sde18` |
| `dtbo_b` | `/dev/block/sde43` |
| `vbmeta_a` | `/dev/block/sde17` |
| `vbmeta_b` | `/dev/block/sde42` |
| `super` | `/dev/block/sda29` |
| `userdata` | `/dev/block/sda34` |
| `linux` | `/dev/block/sda35` |
| `metadata` | `/dev/block/sda18` |
| `persist` | `/dev/block/sda22` |
| `uefivarstore` | `/dev/block/sde62` |

Fastboot-reported sizes from the first capture:

| Partition | Size |
| --- | --- |
| `boot_a` / `boot_b` | 192 MiB each |
| `linux` | 108.36 GiB |
| `super` | 8.50 GiB |
| `userdata` | 117.39 GiB |

## Installer implication

The likely Windows target is the raw `linux` partition, not Android
`userdata`, `super`, `metadata`, `persist`, or modem/calibration partitions.

Do not flash UEFI to `boot_a` while Android uses slot `a`. The likely Windows
boot target is `boot_b`, but verify this by booting postmarketOS and checking
its active slot before flashing.

