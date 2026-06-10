# Pipa QCSPI Signed-CID Checkpoint

Date: 2026-06-04

## Current Device State

- Tablet is booted into Android 14 on slot A.
- ADB verified: product/device `pipa`.
- Android userdata partition 34 was not touched.
- Slot B currently contains the rooted recovery image:
  `<ARTIFACT_DIR>\boot_partitions-adbkey.img`
- Do not boot slot B directly as Windows until the v9 UEFI candidate is flashed.

## Root Cause Confirmed

The isolated custom QCSPI install failed before the driver could bind:

- `pnputil` exit: `-536870353`
- HRESULT: `0xE000022F`
- Meaning: third-party INF does not contain digital signature information.
- `qcspi` service was not created or loaded.
- No touch child appeared.
- No restart was requested.

The failed package was the modified unsigned INF:
`pad6-spi-driver\qcspi8250-pipa.inf`.

## Fix Implemented

The SPI controller keeps pipa's native hardware ID and now advertises the
compatible ID expected by the original signed Kona package:

```asl
Name (_HID, "QCOM050F")
Name (_CID, "QCOM250F")
```

Modified source:
`external\Mu-Qcom\Platforms\Xiaomi\pipaPkg\AcpiTables\TouchMinSSDT.asl`

The isolated QCSPI test and staging scripts now use the original signed Kona
package:

- `qcspi8250.inf`
- `qcspi8250.cat`
- `qcspi8250.sys`

Updated scripts:

- `scripts\Test-PipaQcspiOnly.ps1`
- `scripts\Stage-PipaQcspiOnlyStartup.ps1`

## Built Candidate

Candidate v9 boot image:

`<ARTIFACT_DIR>\pipa_muold_touchmin_v9-signed-qcspi-cid.img`

SHA256:

`F0D9FBA89BE1AC1D2EF8BF87F3E70E94AA6E9790B6D318CEFECBF64C2A7CEA60`

Candidate v9 UEFI FD:

`<ARTIFACT_DIR>\pipa_muold_touchmin_v9-signed-qcspi-cid.fd`

SHA256:

`F6CE1A3A0ADC564976102DA6D386024EC101E3DD92339E65FB11256A154441BB`

Compiled TouchMin SSDT:

- AML size: 620 bytes
- SHA256: `8E648FED7E9890571C511680E3E73F3B15A2846C61ADDC3CA632640B551A338D`
- Contains `QCOM050F`, `QCOM250F`, and `NVT36532`.
- ACPI compilation: 0 errors, 0 warnings.
- UEFI build: success.

Stable rollback UEFI remains unchanged:

`<ARTIFACT_DIR>\pipa_muold_touchmin_v8.img`

SHA256:

`A39A8780D631431D2848861E7BFCBE2D6BB7E31C01946B9075CE811F268FB93B`

## Staging Status

The corrected signed package was not staged to Windows because the PC UAC
prompt was canceled twice. Windows was not booted after implementing the fix.

## Next Session

1. Enter fastboot from Android.
2. Boot the existing rooted recovery on slot B and expose mass storage.
3. Run `scripts\Stage-PipaQcspiOnlyStartup.ps1` and approve the PC UAC.
4. Safely eject mass storage and return to fastboot.
5. Flash `pipa_muold_touchmin_v9-signed-qcspi-cid.img` to `boot_b`.
6. Set slot B active and boot Windows.
7. Approve the tablet UAC for the isolated signed QCSPI test.
8. Review `C:\woa\qcspi-only\RESULT.txt`; do not restart until reviewed.
9. If QCSPI binds with Code 0, test one Windows restart before installing touch.

