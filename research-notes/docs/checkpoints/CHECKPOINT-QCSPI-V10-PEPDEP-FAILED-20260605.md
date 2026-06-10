# Pipa QCSPI v10 PEP Dependency Failed Checkpoint

Date: 2026-06-05

## State

- Device: Xiaomi Pad 6 / pipa.
- Android slot A remains intact and active after cleanup.
- Windows slot B still contains Windows, but QCSPI was cleaned offline after the failed test.
- Do not re-install QCSPI again without changing the ACPI/driver strategy.

## v10 ACPI Change

`TouchMinSSDT.asl` was changed to add a minimal PEP dependency path:

- Added `\_SB.PEP0` with `_HID "QCOM1A17"` and `_CID "PNP0D80"`.
- Added `SPI4._DEP = { PEP0 }`.
- Kept `SPI4` resource base at `0x00990000`.
- Kept `SPI4` native `_HID "QCOM050F"` and compatible `_CID "QCOM250F"`.

Compiled AML:

- `external\Mu-Qcom\Platforms\Xiaomi\pipaPkg\AcpiTables\TouchMinSSDT.aml`
- Size: 686 bytes
- SHA256: `FF5AB4A117C305B8EAA1A5759183F3458FD153CCED26960065E2B781BB934E7C`
- Compile result: 0 errors, 0 warnings.

## Built Candidate

- Boot image: `<ARTIFACT_DIR>\pipa_muold_touchmin_v10-pepdep.img`
- Boot image SHA256: `CEEB16B44200531F59FD523B12BD4B29FAE4DC21AAB6F4FA6F7BD2C1E0B5FD52`
- UEFI FD: `<ARTIFACT_DIR>\pipa_muold_touchmin_v10-pepdep.fd`
- UEFI FD SHA256: `BBA243068CB3C02EE4E868ACC9B969FE9920E38A2D9D6C605A3849B041F1E7F6`

## Test Result

The v10 image was flashed to `boot_b` and Windows was booted. The guarded QCSPI
startup runner installed the signed Kona QCSPI package with `Instance\4`
configured as FIFO.

Windows restarted/crashed after the UAC approval during:

```cmd
pnputil /add-driver C:\woa\qcspi-only\driver\qcspi8250.inf /install
```

Latest SetupAPI evidence:

- `qcspi8250.inf` imported as `oem2.inf`.
- Service `qcspi` was created.
- Device selected: `ACPI\QCOM050F\4`.
- Configuration used: `ACPI\QCOM250F`.
- Log stops at:
  `Install Device: Starting device 'ACPI\QCOM050F\4'`

There was no new minidump or LiveKernelReport after the crash.

## Cleanup

Offline cleanup was run against `WINPIPA` mounted as `E:`.

- `oem2.inf` was removed successfully.
- Startup fallbacks were absent after the guarded test removed them.
- Matching INF scan after cleanup only showed old non-QCSPI entries:
  `oem1.inf`, `qcgpio_i.inf`.
- Device was returned to fastboot with current slot `a`.

Dump folder:

`qcspi-v10-pepdep-after-crash-dump-20260605`

## Current Conclusion

The following are no longer the leading causes:

- UAC or pnputil invocation.
- Missing `_CID` for signed Kona package.
- `Instance\4` GPI DMA mode.
- SPI MMIO base mismatch with the current table; current `SPI4._CRS` is already
  `0x00990000`.
- Minimal `SPI4._DEP = { PEP0 }` alone.

Remaining likely causes:

1. Incomplete PEP/clock implementation: `PEP0` object exists, but no working
   Qualcomm PEP driver is loaded because `qcpep` previously caused 0xA0.
2. Missing or incomplete SMMU/IOMMU ACPI and driver path for the QUP/SPI stack.
3. The Kona/Pad5 QCSPI Windows drivers require a fuller ACPI platform model than
   the current pipa minimal UEFI provides.

Next safer direction is not another QCSPI install. Inspect/build a fuller ACPI
platform path first, especially PEP/SMMU/IOMMU, or obtain a useful kernel dump /
debug stack before more driver-start attempts.

