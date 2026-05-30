# pipa-woa

Windows on Arm bring-up kit for Xiaomi Pad 6 (`pipa`, Snapdragon 870 / SM8250).

This repository is an installer and research workspace. It does not ship Windows,
Xiaomi firmware blobs, Qualcomm proprietary drivers, or third-party UEFI
binaries. Those files must come from official sources, community releases, or
your own device.

## Current goal

Replace the existing Linux/postmarketOS partition with Windows ARM64 while
keeping Android intact, then boot Windows through a UEFI image flashed to the
Linux boot slot.

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

## What is not solved yet

- A proven modern Xiaomi Pad 6 Windows driver stack.
- WDDM GPU acceleration for Adreno 650 on Windows.
- Windows camera stack for Qualcomm ISP + Xiaomi sensors.
- Audio DSP, suspend, pen, and thermal tuning.

postmarketOS having working GPU and touch is useful evidence, but Windows still
needs Windows ARM64 drivers and ACPI descriptions.

## Quick start

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
