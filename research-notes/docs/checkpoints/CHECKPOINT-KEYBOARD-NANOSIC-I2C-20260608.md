# CHECKPOINT - Pad 6 Cover Keyboard / Nanosic I2C

Date: 2026-06-08
Device: Xiaomi Pad 6 `pipa`, Android slot A booted with temporary Magisk root via `fastboot boot`.

## Root Boot Image

Do not use `D:\boot.img` as the primary root image; `fastboot boot D:\boot.img`
failed once with `Status read failed (Too many links)`.

The Magisk-patched root image was found on the tablet at:

- `/storage/emulated/0/magisk_patched-29000_Hc9O9.img`

It was pulled to the workspace at:

- `<WORKSPACE>\pipa-magisk_patched-29000_Hc9O9.img`

SHA256:

- `75d1327f584062d7e3d2d92927af9a06d52e28328e2b81d692486432fd8e2b69`

Use this image for temporary Android root:

```powershell
adb reboot bootloader
fastboot set_active a
fastboot boot "<WORKSPACE>\pipa-magisk_patched-29000_Hc9O9.img"
```

## 2026-06-08 Next QCI2C Staging

`boot_partitions.img` was tested from:

- `<PROJECT_ROOT>\boot_partitions.img`

Result: it boots and ADB becomes authorized, but it is not root and does not expose
`msc.sh` in `/system/bin`, `/sbin`, or `/bin`. This confirms the Android 14 GKI
ramdisk issue still applies; use the Magisk-patched boot image above for root work.

With Magisk root, `/dev/block/by-name/windows -> /dev/block/sda36` was exposed via
USB mass storage as PC drive `F:` with label `WINPIPA`. Only `sda36` was exposed,
not the full disk.

The next manual-run package was staged onto the Windows partition at:

- `F:\woa\RUN.cmd`
- `F:\woa\pipa-next-qci2c\run-next.cmd`
- `F:\woa\pipa-next-qci2c\run-next.ps1`
- `F:\woa\pipa-next-qci2c\driver\qci2c8250.inf`
- `F:\woa\pipa-next-qci2c\driver\qci2c8250.sys`
- `F:\woa\pipa-next-qci2c\driver\qci2c8250.cat`

From Windows on the tablet, run:

```cmd
C:\woa\RUN.cmd
```

The script self-elevates, disables old Pipa autorun leftovers, enables test signing,
installs only `qci2c8250.inf`, and writes:

- `C:\woa\next-qci2c\RESULT.txt`
- `C:\woa\next-qci2c\DONE.txt`
- `C:\woa\next-qci2c\REBOOT_NEEDED.txt` if `pnputil` returns 3010

Public Desktop and ProgramData Startup shortcuts hit NTFS ACL denials from the PC
side, so do not rely on autorun for this test. Use `Win+R -> C:\woa\RUN.cmd`.

## Result

The Xiaomi Pad 6 keyboard cover is not exposed as the Pad 5/Nabu USB Nanosic device.

Stop treating `NanosicFilter.inf` as the primary Pad 6 cover solution:

- Existing Windows INF target: `USB\VID_3206&PID_3FFC&MI_01`
- Previous Windows dump with only Xiaomi cover attached: no `VID_3206&PID_3FFC`
- Android root shows the real path is `nanosic,803` on Qualcomm GENI I2C, then Android creates virtual HID devices.

## Android Root Facts

Live root check:

- `adb shell su -c id` -> `uid=0(root)` with Magisk context
- Active slot: `_a`
- Root boot was temporary, not flashed.

Nanosic physical transport:

- I2C controller: `/soc/i2c@988000`
- Linux adapter: `/sys/class/i2c-adapter/i2c-1`
- Device: `/soc/i2c@988000/nanosic@4c`
- Address: `0x4c`
- Driver: `/sys/bus/i2c/drivers/nanosic,803`
- Compatible: `nanosic,803`
- Parent controller driver on Android: `i2c_geni`

Controller resources from DT:

- MMIO: `0x00988000`, length `0x4000`
- Interrupt: `0x25B`
- Alias: `qupv3_se2_i2c`

GPIO resources from DT / dmesg:

- `irq_pin`: GPIO `100`, dmesg global pin `1200`, flags `0x6001`
- `reset_pin`: GPIO `141`, dmesg global pin `1241`
- `status_pin`: GPIO `46`, dmesg global pin `1146`
- `vdd_pin`: GPIO `127`, dmesg global pin `1227`
- `sleep_pin`: GPIO `155`, dmesg global pin `1255`
- `hall_n_pin`: GPIO `110`, dmesg global pin `1210`
- `hall_s_pin`: GPIO `121`, dmesg global pin `1221`

Virtual HID devices created by Android:

- `0006:15D9:00A1` - Xiaomi Touch - `hid-multitouch`
- `0006:15D9:00A2` - Xiaomi Mouse - `hid-generic`
- `0006:15D9:00A3` - Xiaomi Keyboard - `hid-generic`
- `0006:15D9:00A4` - Xiaomi Consumer - `hid-generic`

Report descriptors were pulled to:

- `logs/android-keyboard-rootdump2-20260608-092004/pipa-keyboard-rootdump-root/hid/0006_15D9_00A1.0003.report_descriptor.bin`
- `logs/android-keyboard-rootdump2-20260608-092004/pipa-keyboard-rootdump-root/hid/0006_15D9_00A2.0002.report_descriptor.bin`
- `logs/android-keyboard-rootdump2-20260608-092004/pipa-keyboard-rootdump-root/hid/0006_15D9_00A3.0001.report_descriptor.bin`
- `logs/android-keyboard-rootdump2-20260608-092004/pipa-keyboard-rootdump-root/hid/0006_15D9_00A4.0004.report_descriptor.bin`

Descriptor sizes:

- Touchpad: 260 bytes
- Mouse: 56 bytes
- Keyboard: 61 bytes
- Consumer/media: 25 bytes

## Binary Evidence

Pulled Android binaries:

- `vendor.xiaomi.hardware.keyboardnanoapp@1.0-service`
- `vendor.xiaomi.hardware.keyboardnanoapp@1.0.so`
- `libhidconverter.so`
- `Keyboard_Upgrade_0x01.bin`
- `Keyboard_Upgrade_0x02.bin`
- `Keyboard_Upgrade_0x20.bin`
- `MIUIInput.kl`

Important strings:

- Android service opens `/dev/nanodev0`
- Android service logs `KeyboardNanoapp init`, `nanoapp service start`, `succeed write data to device`
- HAL exposes `sendCmd`, `setCallback`, `dataReceive`, `errorReceive`
- `libhidconverter.so` exports:
  - `GenerateHIDKeyboardData`
  - `GenerateHIDMouseData`
  - `GenerateHIDTouchPadData`

Conclusion: Android kernel driver + HAL translate Nanosic raw frames into virtual HID. Windows needs an equivalent host path, not just an INF binding tweak.

## Windows Driver Facts

Available Qualcomm I2C controller driver:

- `<PROJECT_ROOT>\kona-drivers\Drivers\SOC\I2C\qci2c8250.inf`
- Binds to `ACPI\QCOM2511`
- `Instance\2` is configured:
  - `GPII = 3`
  - `OpMode = FIFO`
  - `QUPType = QUP_0`

This matches Android `qupv3_se2_i2c` at `0x988000` better than any USB Nanosic path.

## Next Small Test

Do not install `NanosicFilter` again for the cover.

Next low-blast-radius test should be:

1. Add a minimal ACPI SSDT exposing only the I2C controller:
   - `_HID = "QCOM2511"`
   - `_UID = 2`
   - `_CRS` MMIO `0x00988000`, length `0x4000`, IRQ `0x25B`
   - `_DEP` should include `PEP0`
   - Probably name it `I2C2` to match `qupv3_se2_i2c`
2. Boot Windows and install only `qci2c8250.inf`.
3. Verify:
   - `ACPI\QCOM2511\2` / qci2c reaches `CM_PROB_NONE`
   - service `qci2c` is running or at least starts without boot loop
   - no BSOD/reboot loop
4. Only after qci2c is stable, add a child `nanosic@4c` ACPI device and build/test a custom Nanosic/VHF driver.

## Prepared V16 Controller-Only Image

Created a safer ACPI test image that exposes only the I2C controller, with no Nanosic child device yet.

Source scripts:

- `external/Mu-Qcom/codex-build-v16-i2c2-controller-only.sh`
- `external/Mu-Qcom/codex-repack-v16-i2c2-controller-only-local.ps1`

Final artifacts:

- `<ARTIFACT_DIR>\pipa_muold_touchmin_v16-i2c2-controller-only-local.fd`
- `<ARTIFACT_DIR>\pipa_muold_touchmin_v16-i2c2-controller-only-local.img`

Hashes:

- FD SHA256: `5C17FA0D01EC9D303096F87178F59395C912057D99970B0556A8AD7407D76E59`
- IMG SHA256: `907C8A58B0EB44D2FD0B332249ECD12E795BC91BF6CE0D4E0F133D0FE18BB5FF`

ACPI delta in v16:

- Adds `Device (I2C2)`
- `_HID = "QCOM2511"`
- `_UID = 0x02`
- `_DEP = { PEP0 }`
- `_CRS` MMIO `0x00988000`, length `0x4000`, IRQ `0x25B`
- Does not add `NANO0803` or any keyboard child yet.

## Risk Notes

- qci2c is a low-level bus controller. Test it alone before any Nanosic child.
- The Nanosic child currently has no proven Windows driver in the staged package.
- A future Windows driver likely needs KMDF + SPB/I2C + VHF:
  - SPB/I2C talks to addr `0x4c`
  - GPIO handles power/reset/irq/hall
  - VHF exposes virtual HID devices using the Android descriptors above

