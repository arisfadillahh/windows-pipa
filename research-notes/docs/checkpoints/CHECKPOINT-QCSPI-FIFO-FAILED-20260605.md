# Pipa QCSPI FIFO Failed Checkpoint

Date: 2026-06-05

## Device State

- Device returned to Android slot A after testing.
- Android userdata was not exposed or modified.
- Windows remains on slot B with v9 UEFI:
  `<ARTIFACT_DIR>\pipa_muold_touchmin_v9-signed-qcspi-cid.img`

## What Was Tested

QCSPI was tested twice on `ACPI\QCOM050F\4`:

1. Signed Kona QCSPI package with `Instance\4 OpMode = GPI`.
2. Guarded signed Kona QCSPI package with `Instance\4 OpMode = FIFO`.

Both attempts rebooted Windows during:

```cmd
pnputil /add-driver C:\woa\qcspi-only\driver\qcspi8250.inf /install
```

The guarded FIFO runner created `ATTEMPTED.txt` and removed Startup before
installing, so the second crash did not create an install loop.

## Cleanup Status

User successfully removed the installed QCSPI package from Windows:

```cmd
pnputil /delete-driver oem2.inf /uninstall /force
```

Offline verification confirmed:

- `Codex-QCSPI-Only.cmd` Startup fallback is absent.
- No remaining `oem*.inf` contains `qcspi`, `QCOM050F`, or `QCOM250F`.
- `setupapi.dev.log` records successful removal of `oem2.inf` and the
  `qcspi8250.inf_arm64_cf32f56cbd37b085` DriverStore package.

## Evidence

Dump folder:

`<WORKSPACE>\qcspi-fifo-after-delete-dump-20260605`

Key files:

- `SUMMARY.txt`
- `setupapi-qcspi-fifo-snippet.txt`
- `qcspi-full\test-qcspi-only.log`
- `qcspi-full\before\pnputil.txt`
- `qcspi-full\driver\qcspi8250.inf`

## Conclusion

The v9 ACPI `_CID = QCOM250F` fix works: Windows exposes `ACPI\QCOM250F` as a
compatible ID for `ACPI\QCOM050F\4`.

The QCSPI crash is not solved by switching `Instance\4` from GPI DMA mode to
FIFO mode. The remaining likely blockers are PEP/clock/resource dependencies
or incorrect ACPI resources for the SPI controller.

Do not install QCSPI again until PEP0/MMU0/resource handling is inspected or
kernel debugging/minidump evidence is available.

