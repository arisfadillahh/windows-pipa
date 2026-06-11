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

## Status / next session

- v27 image built and staged on `D:\windows pipa\`. **Not yet flashed** (device handed back
  to Android for use; flashing + boot verification deferred to next session).
- Next: flash v27 to `boot_b`, boot Windows, run dump. Expect `ACPI\QCOM250D\0` Started with
  `qcgpio8250` bound (real GPIO). Watch for: qcgpio failing on the junk GIO0 `_CRS`
  (240×3 + foreign QUP vectors) — if so, the follow-up is a cleaned GIO0 `_CRS` (v28).
- Rollback ladder if v27 misbehaves: v26 (display OK, GIO0=genpass) or v25 (baseline),
  both on `D:`. Android slot A untouched throughout.
