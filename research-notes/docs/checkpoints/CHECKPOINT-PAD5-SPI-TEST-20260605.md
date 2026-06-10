# CHECKPOINT - Pad5 SPI isolated test for pipa

Date: 2026-06-05

## State

- Device: Xiaomi Pad 6 / pipa.
- Android slot A must stay intact.
- Windows slot B is the test target.
- Previous QCSPI Kona tests:
  - `qcspi8250.sys` via signed Kona `ACPI\QCOM250F` package crashed at driver start.
  - `Instance\4 OpMode=FIFO` was verified in source and still crashed.
  - Offline cleanup removed the staged QCSPI package and Startup fallback.

## New hypothesis

Try the Pad 5 / QC8150 SPI package because it already matches pipa's native SPI HID:

- Driver path:
  `<PROJECT_ROOT>\pad5-drivers\components\QC8150\Device\DEVICE.SOC_QC8150.NABU_MINIMAL\Drivers\SOC\SPI`
- INF: `MiPad5_spi.inf`
- SYS: `qcspi8150.sys`
- CAT: `MiPad5_spi.cat`
- Matches: `ACPI\QCOM050F`

This is still risky because the INF uses `Instance\4 OpMode=GPI`, but the driver binary is different from Kona's `qcspi8250.sys` and is known from Pad 5.

## Scripts added

- `scripts\Stage-PipaPad5SpiOnlyFromLetters.ps1`
- `scripts\Test-PipaPad5SpiOnly.ps1`
- `scripts\Run-PipaPad5SpiOnly.cmd`

Updated cleanup/dump:

- `scripts\Disable-PipaQcspiOffline.ps1`
- `scripts\Dump-PipaQcspiOffline.ps1`

## Staged payload

Windows volume was mounted as `E:` (`WINPIPA`) from Android root helper mass-storage.

Staged to:

- `E:\woa\pad5-spi-only\driver\MiPad5_spi.inf`
- `E:\woa\pad5-spi-only\driver\MiPad5_spi.cat`
- `E:\woa\pad5-spi-only\driver\qcspi8150.sys`
- `E:\woa\pad5-spi-only\Test-PipaPad5SpiOnly.ps1`
- `E:\woa\pad5-spi-only\Run-PipaPad5SpiOnly.cmd`

Startup fallback installed:

- `E:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Codex-Pad5-SPI-Only.cmd`

Then booted Windows slot B:

```powershell
fastboot set_active b
fastboot reboot
```

Monitor result:

- If Windows reaches desktop, accept UAC if shown.
- If it reboots once, let it reboot once; `ATTEMPTED.txt` guard prevents a repeated loop.
- If it crashes into recovery/fastboot, expose Windows offline and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\Disable-PipaQcspiOffline.ps1 -WinDrive <WINPIPA_LETTER>
```

## Expected result location

If test reaches completion:

- `C:\woa\pad5-spi-only\RESULT.txt`
- `C:\woa\pad5-spi-only\test-pad5-spi-only.log`
- `C:\woa\pad5-spi-only\after\pnputil.txt`

Working means `ACPI\QCOM050F\4` becomes `CM_PROB_NONE` and service `qcspi` is running. Anything else is not a clean success.

