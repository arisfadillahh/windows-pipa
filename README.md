# pipa-woa

Windows on Arm bring-up kit for Xiaomi Pad 6 (`pipa`, Snapdragon 870 / SM8250).

This repository is an installer and research workspace. It does not ship Windows,
Xiaomi firmware blobs, Qualcomm proprietary drivers, or third-party UEFI
binaries. Those files must come from official sources, community releases, or
your own device.

## Current goal

Develop Windows ARM64 on a separate partition while preserving a known-good
Arch Linux installation and a tested recovery path. The current recovered
baseline uses kernel `6.15.11-5-pipa-alarm`; Windows hardware bring-up remains
experimental.

## Recovery checkpoint — 2026-11-06

Arch Linux recovered from a black-screen Qualcomm 9008 state using native Mac
EDL access and a verified five-sector GPT-header correction. Arch's partition
and kernel were preserved; no factory reset or bootloader relock was needed.
SSH, an ext4 read-write root, the existing kernel and the front-camera bridge
service were verified after boot. A fresh camera capture was not tested.

The [recovery checkpoint](research-notes/docs/checkpoints/CHECKPOINT-EDL-GPT-RECOVERY-20261106.md)
records the exact evidence, backup scope, authentication limits, header-only
repair and readback checks. The Firehose access used for recovery does not
provide Windows GPU, touch, keyboard or camera drivers.

## What works in this repo today

- Collects hardware and partition evidence from Android, fastboot, or
  postmarketOS over SSH.
- Downloads Android platform-tools for Windows.
- Applies a Windows ARM64 ISO image onto a mounted target partition.
- Builds Windows boot files on a mounted ESP partition.
- Optionally injects a local driver folder into the offline Windows image.
- Flashes a supplied UEFI boot image to an explicit boot slot.
- Uses destructive gates so the installer cannot format or flash without
  `-AllowDestructive`.
- Documents the locally downloaded Microsoft Windows ARM64 ISO and pipa UEFI
  candidate in [docs/ARTIFACTS.md](docs/ARTIFACTS.md).

## Public research notes

The [`research-notes/`](research-notes/) folder contains sanitized public notes
from later Xiaomi Pad 6 Windows on ARM bring-up sessions. It includes
checkpoint documents, ACPI/UEFI repack helpers, and diagnostic scripts used to
investigate Qualcomm PEP, GPI, SPI, I2C, GPIO, touch, and keyboard-cover
bring-up.

Those notes are published for reproducibility and community debugging. They do
not include Windows images, Xiaomi firmware, Magisk-patched boot images,
Qualcomm/Microsoft/Xiaomi driver binaries, raw private logs, or device backups.

## What is not solved yet

- A proven modern Xiaomi Pad 6 Windows driver stack.
- WDDM GPU acceleration for Adreno 650 on Windows.
- Windows camera stack for Qualcomm ISP + Xiaomi sensors.
- Audio DSP, suspend, pen, and thermal tuning.

postmarketOS having working GPU and touch is useful evidence, but Windows still
needs Windows ARM64 drivers and ACPI descriptions.

## Quick start

The commands below describe the original installer workflow, including
formatting a Linux target. They are not a validated installation plan for the
current preserved-Arch layout. Read the recovery checkpoint and establish fresh
backups and recovery gates before another Windows experiment.

Run PowerShell as Administrator on the PC:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\Fetch-Dependencies.ps1
.\scripts\Collect-PipaHardware.ps1 -UseAdb
```

Then expose the Linux root partition and ESP from recovery or another safe mass
storage path. Note the drive letters in Windows Disk Management.

Apply Windows to the mounted Linux partition:

```powershell
.\scripts\Install-PipaWindows.ps1 `
  -WindowsIso "D:\ISO\Win11_25H2_English_Arm64_v2.iso" `
  -WindowsDrive W `
  -EspDrive S `
  -DriverPath ".\drivers\vendor" `
  -FormatWindowsDrive `
  -AllowDestructive
```

Flash your tested UEFI image to the Linux boot slot:

```powershell
.\scripts\Flash-PipaBoot.ps1 `
  -UefiImage ".\firmware\pipa_dualrole.img" `
  -BootSlot b `
  -AllowDestructive
```

Read [docs/INSTALL.md](docs/INSTALL.md) before running destructive commands.

## Safety model

- The scripts never choose a boot slot for you.
- The scripts never format a drive unless `-FormatWindowsDrive` or
  `-FormatEspDrive` is present.
- The scripts never flash boot partitions unless `-AllowDestructive` is present.
- Android partitions are not touched unless you explicitly pass their drive
  letter or boot slot. Do not do that.

If anything looks different from the docs, stop and run the collector again.
