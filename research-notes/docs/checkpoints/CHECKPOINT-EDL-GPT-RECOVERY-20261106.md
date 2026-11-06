# Xiaomi Pad 6: Arch recovered after EDL and GPT-header repair

Date: 2026-11-06. Device family: Xiaomi Pad 6 (`pipa`, Snapdragon 870 / SM8250).

Arch Linux returned to its desktop after a targeted correction of five primary GPT headers. The recovery wrote **20 KiB total (20,480 bytes)**, preserved the current partition layout and boot-bank payloads, and did not require a factory reset or bootloader relock. Windows input and crash issues remain unresolved.

## Verified outcome

- The owner confirmed the Arch desktop. Remote access answered with kernel `6.15.11-5-pipa-alarm`.
- Root remained `/dev/sda36`, ext4, mounted read-write. Its partition identity and bounds matched the preserved installation.
- Boot parameters reported `androidboot.vbmeta.device_state=unlocked` and verified-boot state `orange`.
- `pipa-front-camera-bridge.service` was active, running and enabled. A fresh camera capture was **not** tested.

These checks establish the recovered baseline; they do not establish complete filesystem health or Windows hardware compatibility.

## Observed recovery sequence

1. Experimental Windows/UEFI bring-up had ended in a black screen and Qualcomm USB 9008. Early Mac/WinPE transport attempts received no Sahara data. That absence did not establish chipset damage or bootloader relock.
2. After a renewed physical USB connection, native Mac synchronous transport received a valid 48-byte Sahara HELLO: protocol version 2, minimum 1, image-transfer mode. The exact OEM programmer from the Indonesia ROM was uploaded through real Sahara READ_DATA requests.
3. The RAM programmer initially rejected Firehose CONFIGURE because it required additional authentication. REA inspected the managed code of the exact MiFlash client distributed by PipaDB without executing that client. A bounded Mac port of its local signature-header/payload sequence received NAK for three fixed candidates and ACK for the fourth. This is a patched-client authentication shortcut, not certified OEM account authorization; packet contents and credentials are not published. A payload ACK alone was treated as inconclusive; independent official QDL CONFIGURE ACK and a successful 4 KiB read established actual command access.
4. Read-only captures collected the first and last six 4 KiB sectors of all six UFS LUNs. Current GPT headers, complete entry arrays and backup tables were compared with archived snapshots. Boot-bank payloads were also captured and checked before repair.
5. The reviewed repair changed only one primary-header sector on each of LUNs 1–5. Every write was read back. Verification completed in 29.118 seconds: LUN0, all partition arrays, all backup GPTs and boot-bank payloads were unchanged.
6. A separate normal Firehose power reset followed verification. USB returned as a network interface, Arch answered remotely, and the owner confirmed its desktop.

Authentication access was demonstrated only for the observed RAM-programmer session. Reset can discard that state; reusable authorization or guaranteed future EDL access must not be assumed.

A reset before the GPT repair had already returned to a fresh Sahara session instead of Arch. The signed programmer and accepted local authentication step were re-established before collecting the full readbacks. An earlier direct Sahara RESET also received ACK without USB disconnect; that was correctly treated as an unsuccessful device restart. Neither kind of ACK alone establishes a recovered boot.

## The misleading header-CRC trap

All six primary **header CRCs were valid**. However, five headers named the wrong location for their partition-entry array. Header CRC validates the header bytes, including the pointer; it does not prove that the referenced array is correct.

| LUN | Entries × entry size | Declared primary array LBA | CRC-matching array LBA | Backup GPT |
|---|---:|---:|---:|---|
| 0 | 64 × 128 bytes | 2 | 2 | Valid |
| 1, 2, 3, 5 | 32 × 128 bytes | 5 | 2 | Valid |
| 4 | 96 × 128 bytes | 3 | 2 | Valid |

Every declared array was fully covered by the 24 KiB head capture, so the failed CRCs were not caused by truncation. The arrays at LBA2 matched the headers' stored array CRCs and were byte-identical to the independently valid backup arrays.

The minimal correction therefore changed `PartitionEntryLBA` to 2 and recomputed `HeaderCRC32`, preserving every other byte in each written sector. No partition array or backup GPT was restored from an older image. Current GUIDs, usable bounds and Arch geometry were retained. This is a case-specific result, not a general instruction to force GPT arrays to LBA2.

Each write targeted exactly sector 1 on one of physical LUNs 1–5. Only byte offsets 16–19 (header CRC) and 72 (the low byte of the array pointer) differed from its original 4096-byte sector. Fresh preflight readbacks matched the saved originals before any write; each write was immediately read-verified. Postflight compared all twelve GPT regions and both complete 16 MiB boot banks against the expected header-only changes.

Compared with the archive, current arrays contained the previously documented Windows/Arch label/type cleanup, removal of unused type-GUID-zero `last_parti` placeholders, and one changed attribute bit on `boot_b` (bit51). None required reversal. The GPT inconsistency was observed directly; the program or event that originally introduced it remains unproven.

## Boot stages and backup scope

The stock mapping places `xbl_a`/`xbl_config_a` on physical LUN1 and their B counterparts on physical LUN2. Android `boot_a`/`boot_b` reside on physical LUN4. That does not make 4 the UFS boot selector. Read-only storage information showed selector 1 mapped to the A boot LU; recovery left that selector unchanged.

The pre-experiment archive preserved the working kernel, modules, firmware, camera runtime/configuration, boot images, relevant auxiliary boot partitions, misc and GPT snapshots for all six LUNs. Recovery additionally retained current head/tail captures and boot-bank evidence privately. The earlier kernel/camera archive was **not a full image of the Arch root filesystem or a complete backup of personal files**.

Raw device backups, logs, identifiers, authentication material and proprietary binaries are excluded from this public checkpoint.

## Public artifact identities

SHA-256 values identify the exact public inputs; they do not grant authorization or establish compatibility with another device.

| Artifact | SHA-256 |
|---|---|
| Indonesia fastboot ROM `pipa_id_global_images_OS2.0.15.0.UMZIDXM_20260414.0000.00_14.0_id_a55321e1e4.tgz` | `71f9e686f355756616b193b8ac0be4c6cbb4d2e60e8a822d20553f3314848608` |
| Its `images/prog_ufs_firehose_sm8250_ddr_5.elf` | `bd1da5b2a92f3731c7f3f5f7072587e0ade0b025593ea9f1cfd2d24ddaeaea94` |
| QDL v2.9.1 macOS 26 ARM64 release ZIP | `25cc2266af678bb379346fe0a26789eae5f90a8120b9ef807dc107261462e62a` |
| Original `qdl` executable in that Mac ZIP | `72cf8fb57d755641b2e0408772df71fc46d9ef59709070ea66c6f51b17c2dcfe` |
| QDL v2.9.1 Windows x64 release ZIP used for host diagnostics | `5fdc8adffe46cc4a9f37dbbe91a8c91d0cc26befb3fe67f9609046a254a471d6` |
| PipaDB-distributed `MiFlash.7z` | `211adcf05772319287fdf7203e56c410d8194bdb7a2d08816a95bae405f7b2cc` |
| Its inspected `XiaoMiFlash.exe` | `1d4cb6b434f824c530ceebcfb48141fe174ec34bbba442a63e4d2f0cf399021e` |

QDL release source: [linux-msm/qdl v2.9.1](https://github.com/linux-msm/qdl/releases/tag/v2.9.1). The original Mac executable needed a local Mach-O loader correction for a duplicate runpath before starting; that host packaging workaround must be distinguished from device behavior.

Client provenance: [PipaDB EDL guide](https://github.com/PipaDB/Info/blob/main/edl.md). Its full clean-flash workflow was not used: this case retained Arch through the smaller verified header correction.

## Recovery authorization and GPU support

The accepted fixed packet authorized the observed Firehose session. No universal Qualcomm private signing key was recovered, and no GPU-specific authorization was demonstrated. Loader/recovery access alone does not provide a Windows graphics implementation.

Windows [driver signing](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/driver-signing) verifies package integrity and publisher identity. Its [WDDM architecture](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/windows-vista-and-later-display-driver-model-architecture) additionally requires hardware-compatible user-mode and kernel-mode graphics drivers. Those implementations handle the graphics workload; an accepted recovery signature cannot supply their missing code. GPU, touch, keyboard and camera support remain separate engineering milestones.

## Gates before another Windows experiment

- Keep recovered Arch as the default baseline and keep the bootloader unlocked. Make a current backup of personal data as well as boot/recovery metadata.
- Validate both GPT headers and complete arrays, backups, block geometry, UFS boot selection and the actual target partition before planning any persistent write. Preserve current data; do not substitute stock GPTs merely because they are available.
- Prove a recovery path that does not depend on unverified future authentication access. Bound host operations, keep power stable, and prevent maintenance sessions from sleeping.
- Inspect the Windows ESP and restore or verify the known original boot manager before another experimental UEFI boot. The previously staged `ClockProbeChainEFI` wrapper was not part of this recovery and has not been tested on the physical tablet. Older installer examples are not a validated plan for this recovered layout.
- Change one boot/ACPI/controller variable at a time, capture evidence, and prove stable boot plus usable input before progressing with setup.
- Treat GPU support as a separate driver milestone. Firehose authorization permits recovery operations; Windows Adreno acceleration still needs a compatible ARM64 WDDM driver and matching firmware, power and ACPI integration. Working Android/Linux drivers do not establish that stack.
