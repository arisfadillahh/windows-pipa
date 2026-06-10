# Xiaomi Pad 6 Windows on ARM Research Notes

This repository collects public research notes, ACPI experiments, and helper scripts from an ongoing Windows on ARM bring-up effort for the Xiaomi Pad 6 (`pipa`, Snapdragon 870 / SM8250-family platform).

The goal is not to distribute a ready-made Windows image. The goal is to make the debugging process reproducible: document what was tested, what failed, what appears stable, and which hardware blocks still need proper ACPI and driver work.

## Current Scope

- Windows 11 ARM64 dual-boot research for Xiaomi Pad 6.
- ACPI/UEFI experiments for QCOM PEP, GPI, SPI, I2C, GPIO, touch, and keyboard-cover bring-up.
- Offline Windows servicing and rollback helpers used during debugging.
- Public checkpoints describing observed error codes and known-bad driver paths.

## What Is Not Included

This repository intentionally does not include:

- Windows images, ESD/ISO files, WIM/VHD/VHDX artifacts, or installed OS partitions.
- Xiaomi firmware images, Magisk-patched boot images, or device backups.
- Qualcomm, Microsoft, Xiaomi, or other vendor driver binaries.
- Private logs, photos, user-profile data, or raw device dumps.

Users must obtain firmware, Windows installation media, and drivers from their own legal sources.

## Why This Is Useful Publicly

Porting Windows on ARM to unsupported Snapdragon tablets is difficult because the main blockers are not just "missing drivers". The firmware ACPI tables must describe the hardware correctly before Windows can bind drivers safely.

This project helps the public by documenting:

- Which ACPI hardware IDs were observed on Xiaomi Pad 6.
- Which driver classes caused boot loops or bugchecks.
- Which dependency order matters for Qualcomm power, GPI, SPI, and I2C blocks.
- Which test images were bootable versus stuck at Mu-Qcom.
- How to collect safer offline diagnostics without repeatedly reinstalling Windows.

The results can help other developers avoid repeating dangerous tests that already caused boot loops or BSODs, and can guide future open-source UEFI/ACPI work for `pipa`.

## Safety

This is experimental platform bring-up work. Wrong ACPI tables or driver choices can soft-brick a Windows install, break boot, or require flashing a known-good Android/UEFI boot image.

Before using any script here:

- Keep Android userdata intact.
- Keep a known-good Android boot path.
- Keep a known-good Windows boot image.
- Read the relevant checkpoint first.
- Do not run install/format scripts blindly.

## Repository Layout

- `docs/checkpoints/` - chronological notes from major bring-up milestones.
- `scripts/` - helper scripts for offline servicing, dump collection, boot repair, and staged tests.
- `autorun/` - one-shot Windows-side dump helpers used during experiments.
- `mu-qcom-repack/` - local repack scripts for ACPI/UEFI test images; these require external Mu-Qcom build artifacts and do not contain firmware binaries.

## Status Summary

- Windows boots on known-good Mu-Qcom images.
- GPU and some core platform drivers have been explored, but this repository focuses on reproducible research artifacts rather than driver redistribution.
- QCGPI reached a stable `CM_PROB_NONE` state in prior tests.
- QCSPI and QCI2C remain under investigation; several ACPI variants failed or caused boot instability.
- Xiaomi keyboard cover appears to be an I2C/Nanosic path, not a simple USB keyboard path.

## License

The original scripts and notes in this repository are released under the MIT License. Third-party projects, firmware, Windows media, and vendor drivers referenced by path/name are not included and remain under their respective licenses.
