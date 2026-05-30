# Recovery guide

Before destructive work, keep these available on the PC:

- Full stock Xiaomi Pad 6 fastboot ROM matching your region.
- Backup of the original Linux boot slot image.
- Backup of the Linux ESP contents.
- `captures\...` output from `Collect-PipaHardware.ps1`.

## Restore a boot slot

Boot to fastboot and flash the saved boot image:

```powershell
.\tools\platform-tools\fastboot.exe flash boot_b .\backup\boot_b.img
.\tools\platform-tools\fastboot.exe set_active b
.\tools\platform-tools\fastboot.exe reboot
```

Change `boot_b` and `set_active b` only if your Linux slot is different.

## Return to Android

If Android is slot `a`:

```powershell
.\tools\platform-tools\fastboot.exe set_active a
.\tools\platform-tools\fastboot.exe reboot
```

## Avoid these actions

- Do not wipe `super`, `userdata`, `persist`, `modem`, `bluetooth`, or
  calibration partitions.
- Do not flash unknown files to `boot_a` if Android is on slot `a`.
- Do not relock the bootloader after modifying partitions.

