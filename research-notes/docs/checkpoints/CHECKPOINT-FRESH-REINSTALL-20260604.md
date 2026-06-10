# Xiaomi Pad 6 WOA Fresh Reinstall Checkpoint

## Installation

- Device: Xiaomi Pad 6 `pipa`, SM8250/SD870.
- Android userdata is partition `sda34` and must remain untouched.
- ESP is partition `sda35`.
- Windows is partition `sda36`.
- Windows source: ARM64 ESD index 6, Windows 11 Pro.
- Stable Windows UEFI: `<ARTIFACT_DIR>\pipa_muold_touchmin_v8.img`.
- Recovery used temporarily: `<ARTIFACT_DIR>\boot_partitions-adbkey.img`.
- Local Windows administrator created automatically: `Goffath`.

## Automatic Continuation

`C:\Windows\Setup\Scripts\SetupComplete.cmd` creates a one-shot SYSTEM task:

`Pipa WOA Driver Continuation`

On the first `Goffath` logon it waits 45 seconds, then:

1. Disables known boot-break Qualcomm power/platform services if present.
2. Dumps baseline PnP status to `C:\woa\status-before-safe-drivers`.
3. Installs only the no-power allowlist from `C:\woa\drivers`.
4. Dumps post-install status to `C:\woa\status-after-safe-drivers`.
5. Writes completion state under `C:\woa\state`.
6. Deletes the one-shot task and does not reboot automatically.

Allowed automatically:

- `qcdx8250`, `qcdx_ffu8250`, `qdcmlib8250`: GPU package.
- `nt36xxx`: touch package.
- `NanosicFilter`: Xiaomi keyboard package.

Never install automatically:

- `qcppx`, `qcpil`, `PILC`
- `qcpmic*`, `qcpep`, `qcscm`, `qcsmmu`, `qciommu`, `qcspmi`
- `qcbatt*`, USB-C power-role drivers
- modem/cellular/GNSS
- `qcwlan8250`

## Known Driver State Before Reinstall

- Stable UEFI v8 boots Windows.
- `ACPI\QCOM050F\4`: Code 28, no driver. This is the pipa SPI/touch chain target.
- `ACPI\QCOM0593\0`: Qualcomm GPI Bus, OK.
- `ACPI\QCOM050D\0`: System Manager GPIO, OK.
- Touch `NVT36532` does not enumerate yet. Driver install alone may not solve it; ACPI power-on/resources still need investigation.
- Avoid the old broad driver installer and any automatic Kona platform driver sweep.

## Verification After First Logon

Check:

- `C:\woa\logs\setup-complete.log`
- `C:\woa\logs\driver-continuation.log`
- `C:\woa\state\safe-drivers.done`
- `C:\woa\state\driver-continuation-result.json`
- `C:\woa\status-after-safe-drivers\status-problem.txt`

Do not install another driver batch until the fresh baseline has rebooted cleanly once.

## Continuation Audit And GPI8150 Test

The first continuation ran twice and completed, but installed no drivers:

- `qcdx8250.inf`: missing staged file `qcdxwsaum.img`.
- `qcdx_ffu8250.inf`, `qdcmlib8250.inf`, and `NanosicFilter.inf`: WOA signer root was not trusted and the non-interactive SYSTEM task could not accept the warning.
- `nt36xxx.inf`: modified INF hash is not present in its catalog.
- Fresh post-run problem devices remained only `ACPI\QCOM050F\4` and `ACPI\QCOM0593\0`, both Code 28.

Next isolated test staged on 2026-06-04:

- Target only: `ACPI\QCOM0593\0`.
- Driver: Pad 5 `qcgpi8150.inf`, which exactly matches `ACPI\QCOM0593` and was previously verified `OK` on this device.
- Payload: `C:\woa\gpi8150-safe`.
- Autorun: `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Pipa-GPI8150-Autorun.cmd`.
- Manual fallback: `C:\PIPA-GPI.cmd`.
- Log: `C:\woa\logs\gpi8150-safe.log`.
- State: `C:\woa\state\gpi8150-safe-result.json`.
- No automatic reboot and no GPU, touch, PMIC, PIL, PCIe, or other power/platform drivers.

Recovery found the Windows NTFS volume hibernated after forced fastboot. `$MFT`, `$MFTMirr`, and alternate boot sector passed `fsck.ntfs -n`; the hibernation state was removed before staging. Stable UEFI v8 was restored to `boot_b` and slot B was activated before booting Windows.

