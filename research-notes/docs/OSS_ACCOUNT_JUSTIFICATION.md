# OSS/Public Benefit Justification

## Project Name

Xiaomi Pad 6 Windows on ARM Research Notes

## Short Description

This is an open research repository documenting the Windows on ARM bring-up process for Xiaomi Pad 6 (`pipa`). It publishes safe-to-share ACPI experiments, troubleshooting scripts, and checkpoint notes so other developers can reproduce the investigation without sharing proprietary firmware or driver binaries.

## What The Repository Provides

- Public documentation of successful and failed ACPI/UEFI experiments.
- Scripts for collecting Windows PnP, setup, and boot diagnostics.
- Notes on Qualcomm platform dependencies such as PEP, GPI, SPI, I2C, and GPIO.
- Safety guidance for rollback-first testing on a dual-boot Android/Windows device.
- A clear record of known-bad paths, including driver classes that caused boot loops or Windows bugchecks.

## Public Benefit

This project helps the open-source device-porting community by reducing duplicated trial and error. Unsupported Windows on ARM ports often fail because hardware description, firmware, and driver dependencies are poorly documented. Publishing structured notes and scripts makes it easier for other developers to:

- Understand Xiaomi Pad 6 hardware bring-up blockers.
- Compare their ACPI tables and device IDs.
- Avoid tests already known to trigger boot loops or BSODs.
- Build safer diagnostic workflows before flashing or modifying partitions.
- Contribute improvements to open UEFI/ACPI ports without distributing proprietary files.

## Why It Qualifies As OSS Work

The repository contains original scripts, documentation, and research artifacts under an open-source license. It intentionally excludes copyrighted or proprietary binaries such as Windows images, Xiaomi firmware, Qualcomm drivers, boot images, and private dumps.

The work is useful beyond one device owner because the Xiaomi Pad 6 shares platform concepts with other Qualcomm SM8250-family Windows on ARM ports. The public notes can help future maintainers and contributors debug similar ACPI and driver dependency issues.

## Responsible Publishing Statement

This repository is a research and documentation project. It does not provide a turnkey Windows image, bypass licensing, or redistribute vendor binaries. Users must source firmware, Windows media, and drivers legally and accept the risk of experimental hardware bring-up.
