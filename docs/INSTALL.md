# Install guide

This guide targets a Xiaomi Pad 6 (`pipa`) that already dual-boots Android and
Linux/postmarketOS. Windows replaces the Linux partition. Android should remain
untouched if the correct Linux drive and Linux boot slot are selected.

## Required files

- Official Windows 11 ARM64 ISO.
- Android platform-tools for Windows. `Fetch-Dependencies.ps1` downloads these.
- A tested Xiaomi Pad 6 UEFI boot image, placed for example at
  `firmware\Mu-pipa.img`.
- Optional Windows ARM64 drivers in `drivers\`.

This repo does not redistribute Windows, Xiaomi firmware, Qualcomm blobs, or
third-party UEFI binaries.

## 1. Prepare the PC

Run PowerShell as Administrator:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\Fetch-Dependencies.ps1
```

## 2. Capture device evidence

From Android with USB debugging enabled:

```powershell
.\scripts\Collect-PipaHardware.ps1 -UseAdb
```

From fastboot:

```powershell
.\scripts\Collect-PipaHardware.ps1 -UseFastboot
```

From postmarketOS over USB networking or Wi-Fi SSH:

```powershell
.\scripts\Collect-PipaHardware.ps1 -UseSsh -SshHost 172.16.42.1 -SshUser user
```

Save the `captures\...` directory before destructive work.

## 3. Expose Linux and ESP partitions to Windows

Use your existing recovery or postmarketOS workflow to expose the Linux root
partition and ESP partition to the PC. In Windows Disk Management, assign drive
letters:

- Windows target / old Linux root: example `W:`
- ESP / EFI partition: example `S:`

Do not select Android `userdata`, `super`, `boot_a`, `boot_b`, `vendor_boot`,
`dtbo`, `vbmeta`, modem, or persist partitions.

## 4. Apply Windows

Dry run first:

```powershell
.\scripts\Install-PipaWindows.ps1 `
  -WindowsIso "C:\ISO\Win11_Arm64.iso" `
  -WindowsDrive W `
  -EspDrive S `
  -DriverPath ".\drivers\vendor" `
  -DryRun
```

Actual install:

```powershell
.\scripts\Install-PipaWindows.ps1 `
  -WindowsIso "C:\ISO\Win11_Arm64.iso" `
  -WindowsDrive W `
  -EspDrive S `
  -DriverPath ".\drivers\vendor" `
  -FormatWindowsDrive `
  -AllowDestructive
```

Use `-FormatEspDrive` only when you are sure the selected ESP is the Linux ESP,
not an Android-critical partition.

## 5. Flash UEFI to the Linux boot slot

Boot the tablet to fastboot. If Android uses slot `a` and Linux uses slot `b`,
flash only `boot_b`:

```powershell
.\scripts\Flash-PipaBoot.ps1 `
  -UefiImage ".\firmware\Mu-pipa.img" `
  -BootSlot b `
  -AllowDestructive
```

If your slot layout is different, pass the Linux slot explicitly.

## 6. First boot

Expect incomplete hardware support until drivers and ACPI are improved. Basic
display may be framebuffer-only. Touch, GPU acceleration, audio, suspend, and
camera are separate bring-up tasks.

## Rollback

See [RECOVERY.md](RECOVERY.md). Keep stock boot images and the Android fastboot
ROM available before you flash anything.
