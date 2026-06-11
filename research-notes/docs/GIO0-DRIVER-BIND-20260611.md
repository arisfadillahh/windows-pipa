# pipa GIO0 GPIO controller — driver binding saga (v26 → v27) — 2026-06-11

Goal: get a real GpioClx driver (`qcgpio8250`) bound to GIO0 so Windows has a working
GPIO controller. This is the gateway for both the keyboard attention line (TLMM GPIO 100)
and the touch GpioInt.

## Two big findings from the v26 flash

### 1. Editing SEC5 / TouchMin does NOT kill the display (old theory busted)

v26 regenerated SEC5 (changed GIO0 `_CID`) and **booted to a working desktop** — the user
ran the dump from inside Windows. Every prior "stuck at Mu-Qcom" image (v20–v24) that
replaced SEC5 must have failed for a *different* reason, not "SEC5 is untouchable."
This unblocks future TouchMin edits (e.g. the SPI4 touch IRQ fix 605→637).

### 2. v26's `_CID` change was correct but ignored due to Windows sticky driver binding

v26 dump (`ACPI\QCOM050D\0`):
- Hardware IDs: `ACPI\QCOM050D`, Compatible IDs now include **`QCOM250D`** ✓ (the _CID
  edit landed; this confirms the running image is v26).
- BUT driver = `genpass.inf`, `DEVPKEY_Device_ConfigurationId = genpass.inf:ACPI\QCOMFFE3,GenPass`
  — i.e. the binding created back when the device advertised `QCOMFFE3` (v19/v25 era).
- I2C2 still healthy: `ACPI\QCOM0511\2` Started, IRQ 635, qci2c RUNNING. (Confirms v25 fix
  holds across the rebuild.)
- Only remaining problem device: `ACPI\QCOM050F\4` (SPI4 touch), Code 28.

Root cause: Windows binds a driver **per device instance** (`Enum\ACPI\QCOM050D\0`) and
does not re-rank on later boots just because a *compatible* ID appeared. Adding `QCOM250D`
as a `_CID` left the instance path unchanged, so the stale GenPass node kept winning.
(The Kernel-PnP log even shows qcgpio8250 / `oem4.inf` matching `ACPI\QCOM250D` was
*configured* at one point, then GenPass reconfigured the instance — classic sticky churn.)

## Fix: v27 — change GIO0 `_HID`, not `_CID`

`pipa_muold_touchmin_v27-gio0-hid250d-irq635-local.img`

- GIO0 `_HID` QCOM050D → **QCOM250D**, `_CID` QCOMFFE3 → QCOM050D.
- New `_HID` ⇒ new instance path `ACPI\QCOM250D\0` ⇒ no inherited driver node ⇒ Windows
  ranks drivers fresh ⇒ `qcgpio8250` (matches `ACPI\QCOM250D`, Qualcomm rank > generic
  GenPass) should bind. GenPass can no longer match (its `QCOMFFE3` id is gone).
- Everything else identical to v25/v26: I2C2 appended SSDT keeps IRQ 635; SEC1–SEC4
  byte-identical to v26; SEC5 differs (GIO0 ids); SEC7 differs only by OEM table id.

Build verification: confirmed via decompiled SEC5 that GIO0 is now `_HID QCOM250D` /
`_CID QCOM050D`, and PEP0/QGP0/SPI4/NVTS are untouched.

## v27 flash result (same day, later session)

v27 flashed and booted (display fine — third SEC5 regen in a row that boots).

- The `_HID` trick worked exactly as designed: fresh instance `ACPI\QCOM250D\0` exists,
  old `ACPI\QCOM050D\0` is a Disconnected phantom, GenPass can no longer match.
- All of GIO0's boot-config resources reserved cleanly (240×3, 556, 578, 590, 601, 603 +
  MEM 0xF000000) — no more 0xC0000018 anywhere. I2C2 still Started on IRQ 635.
- BUT the new instance is **Code 28** with Kernel-PnP `id=400 ... Driver Name: null` —
  no driver in the store matches at all.

Root cause found in old session logs: a 2026-06-09 cleanup ran
`pnputil /delete-driver oem4.inf /uninstall` and removed the **qcgpio8250** package from
the driver store (it was deleted to de-escalate the Code-12 churn era — a reason that the
IRQ fixes have since made obsolete). The same logs show that when qcgpio8250 was installed
back then, the **service loaded and ran without any BSOD** — the devnode only failed on
the (now-fixed) resource conflict. So reinstalling is low-risk.

The original driver package still exists on the Windows partition:
`C:\woa\qcgpio250d\driver\` (qcgpio8250.inf + qcgpio.sys + qcgpio.cat).

**Staged fix (no reflash needed — boot_b already holds v27):** `C:\woa\fix-gpio.cmd`
self-elevates and runs `pnputil /add-driver ... /install` against the waiting
`ACPI\QCOM250D\0`, rescans, then runs the standard dump. One UAC click.

## v28 contingency (built, not flashed): clean GIO0 _CRS

Decoding the raw `_CRS` buffer in stock TouchMin GIO0 revealed a second latent bug:
the memory descriptor is `0x0F000000 + 0x01000000` — but kona TLMM lives at
**`0x0F100000 + 0x300000`**. If qcgpio treats the resource base as the TLMM base
(the Qualcomm convention — cf. the 8150 reference DSDT using the exact TLMM base
`0x03100000 + 0x300000`), every register access would be off by 1 MB. The junk
interrupt tail (578 L/S, 603 Edge/S, 601 L/S, 556 + 590 Edge/Exclusive) also remains.

`pipa_muold_touchmin_v28-gio0-cleancrs-irq635-local.img` (staged on `D:`, verified by
decompile) fixes both: GIO0 `_CRS` = `Memory32Fixed(0x0F100000, 0x300000)` + summary
IRQ 240 ×3 Level/Shared only; identity stays `_HID QCOM250D`; OFNI (180 pins) intact;
everything else identical to v27.

## Next session decision tree

1. Read the fix-gpio dump from the v27 boot (if the user ran it):
   - qcgpio bound + **Started** → GPIO controller up; validate, then consider v28 anyway
     for the correct TLMM base before trusting actual GPIO I/O (keyboard GPIO 100 /
     touch GpioInt 39).
   - qcgpio bound + **Code 10/12** or misbehaving → flash v28 (driver will re-bind to the
     same `ACPI\QCOM250D\0` instance) and retest.
   - BSOD/bootloop → boot Android, remove the driver offline
     (`dism /Image:<mounted WINPIPA> /Remove-Driver`), rollback boot_b to v26/v25.
2. Rollback ladder unchanged: v27 → v26 → v25 → v19, all on `D:`. Android slot A untouched.
