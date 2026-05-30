# Local artifacts

These artifacts were downloaded locally on 2026-05-30. They are intentionally
not committed to GitHub because they are large and/or third-party binaries.

## Windows ISO

- Path: `D:\ISO\Win11_25H2_English_Arm64_v2.iso`
- Source: Microsoft Windows 11 Arm64 software download page
- Edition: Windows 11 Arm64 25H2, English (United States)
- Size: 7,994,415,104 bytes
- SHA-256:
  `638AA2C88E94385B00F4F178D071E3DF0B7D9E335577A83BD533B7F2EB65ADF0`
- Verification: matches the Microsoft page's SHA-256 table for
  `English 64-bit`.

## pipa UEFI boot image

- Path used by scripts: `firmware\pipa_dualrole.img`
- Downloaded copy: `firmware\unverified\pipa_dualrole.img`
- Source: XDA pipa Windows guide MEGA EFI link
- Cross-check: byte-identical to the `pipa_dualrole.img` inside the GitHub
  `TheMojoMan/xiaomi-pipa` `Pipa-efi-multiboot` release already downloaded
  under `firmware\multiboot\extracted\`.
- Size: 2,783,232 bytes
- SHA-256:
  `312A1EFD264BD5F1261AFE6FAD79FA431A1D7D4CAF82362DDAEC742A001B1D22`
- Header check: Android boot image magic `ANDROID!`; a PE/UEFI payload marker
  `MZ` exists at byte offset `118101`.

The XDA guide that provides the EFI link is marked obsolete. Treat this boot
image as a community UEFI candidate, not a guaranteed full Windows driver stack.

## Current storage note

After the ISO download, available local space is limited:

- `C:` has about 4.9 GiB free.
- `D:` has about 25 GiB free.

Use `D:\pipa-windows-build` for the prepared-image route so large VHD/sparse
outputs do not fill `C:`.
