# pipa touch prep — old qcspi bootloop root-caused, v29 staged (2026-06-11)

No-flash research session. Goal: clear the path for the SPI4/NT36532 touch milestone by
explaining the historical qcspi disaster and pre-building the corrected ACPI.

## The 2026-06-05 qcspi crash, decoded

The workspace kept a minidump from the qcspi attempt (`qcspi-v10-pepdep-after-crash-dump`):

- **BugCheck `0xA0` INTERNAL_POWER_ERROR**, params `0xAA64 / 0x8003 / 0x84000013 / -1`
  (parsed straight from the `PAGEDU64` dump header; build 26100).
- System.evtx from the same dump shows **Kernel-Power 41 dirty reboots every ~7 seconds**
  — a hard bootloop, matching the "qcspi caused BSOD/bootloop" project lore.

### Root-cause hypothesis (strong, with a clean A/B in our own data)

The image that crashed was the "**pepdep**" variant: `SPI4` declared
`_DEP (PEP0, QGP0)`. PEP0 is `QCOM0519/_CID PNP0D80` — the Windows SoC PEP framework
device — but on pipa it raw-starts with no functional PEP behavior behind it for these
nodes. A PoFx-integrated bus driver (qcspi) starting on a device with a PEP `_DEP` engages
the power framework path → `INTERNAL_POWER_ERROR` → bootloop (driver is BOOT_START-ish,
so every boot crashed until the package was removed).

The A/B inside this very project: **`I2C2` is declared with NO `_DEP` ("nodep" — it's in
v19's name) and qci2c runs flawlessly** on the same image family. QGP0 (no `_DEP`) +
qcgpi: also fine. The only QUP client that ever had a PEP `_DEP` is the only one that
bootlooped.

## v29 staged: `pipa_muold_touchmin_v29-touchprep-nodep-irq637-local.img`

Built on top of v28 (clean GIO0 `_CRS` + `QCOM250D` identity + I2C2 IRQ 635), adding two
SPI4 changes — both **inert until a qcspi driver is actually installed** (SPI4 is Code 28
today), so flashing v29 later still tests only one active component (GPIO):

1. **`_DEP (PEP0, QGP0)` removed** from SPI4 — same recipe that makes qci2c work.
2. **IRQ 605 → 637** (`0x27D`): the same raw-DT-hwirq vs GSIV(+32) bug we fixed for I2C2;
   `spi@990000` is GIC SPI 605 in the Android DT → Windows wants 637.

Verified by decompiling the built SEC5: SPI4 has no `_DEP`, IRQ `0x0000027D`, and the v28
GIO0 cleanup (TLMM `0x0F100000+0x300000`, summary IRQ 240×3) is carried over. NVTS child
(SpiSerialBus + GpioInt 39 on `\_SB.GIO0`) untouched.

## Remaining pieces for the touch milestone (next sessions)

1. **GPIO first**: run the staged `C:\woa\fix-gpio.cmd` on the v27/v28 boot so qcgpio8250
   binds to `ACPI\QCOM250D\0`. Touch's GpioInt 39 resolves against GIO0 — no working
   GpioClx, no touch interrupt.
2. **qcspi package**: not present on `D:`; expected on the Windows partition (to be
   located next time F: is exposed). Retry only on a v29 boot (nodep + correct IRQ), with
   the rollback guard: offline `dism /Remove-Driver` + boot_b rollback ladder
   (v27→v26→v25 on `D:`).
3. **NT36532 function driver**: the Xiaomi Pad 5 (nabu) WOA stack has working Novatek SPI
   touch; its public driver pack is the donor candidate:
   - https://github.com/map220v/MiPad5-Drivers (Windows driver pack, nabu)
   - https://github.com/woa-msmnile/Nabu (Project-Aloha drivers submodule)
   - https://github.com/Rasenkai/caf-tsoft-Novatek-nt36xxx (kernel-side NT36xxx reference)
   pipa's panel is NT36532 (per Android `NVT-ts-spi`); the nabu driver's supported HIDs
   and SPI parameters need comparing against our `NVTS` child (`_HID NVT36532`,
   SpiSerialBus 8.39 MHz mode-0 CS0, GpioInt 39).

## Status

- Built & staged on `D:\windows pipa`: v28 (GPIO clean) and v29 (GPIO clean + touch prep).
  **Nothing flashed this session**; boot_b remains v27. Device parked in Android slot A.

## UPDATE (same day, later): qcspi retried on v29 — crashes even without _DEP

Sequence: v29 flashed (checkpoint dump clean: GIO0 Started on the exact TLMM base with
junk vectors gone, I2C2 635, SPI4 ready at IRQ 637 with no `_DEP`), then
`fix-spi.cmd` ran `pnputil /add-driver qcspi8250.inf /install` → **immediate restart at
the install/start moment**. The fix-spi log ends exactly at the add-driver step. The
install transaction rolled back (no `qcspi` service exists afterwards). No new minidump
was written (the only dump on disk is byte-identical to the 2026-06-05 one — same
`0xA0 / 0xAA64, 0x8003, 0x84000013` signature).

So the PEP `_DEP` removal was **not sufficient**. Binary analysis of `qcspi8250.sys`
pins the failure path:

- it does **not** import `KeBugCheckEx` — something else raises the bugcheck;
- it **does** import `PoFxRegisterComponentPerfStates`,
  `PoFxIssueComponentPerfStateChange`, `PoFxQueryCurrentComponentPerfState` —
  i.e. qcspi votes SE **clock/performance states through PoFx**, which forwards to the
  platform PEP = **qcpep.sys** (running on this system since the v19 baseline).

Working theory (sharp): qcspi's perf-state registration reaches qcpep, which cannot
satisfy the SPI SE clock domain on this half-configured platform and raises
`INTERNAL_POWER_ERROR` itself (0xAA64 param style = vendor bugcheck). qci2c survives
because it (presumably — to verify via its binary) never registers perf states.

INF side-by-side (qcspi vs qci2c) showed no smoking config difference: both FIFO OpMode,
both DEMAND_START, both SpbCx-dependent; qci2c also carries wrong-looking
`QUPType=QUP_0` for our QUP1 SE yet works — so the per-instance QUP config is likely
unused in FIFO mode and not the differentiator.

**v30 rescue worked exactly as designed**: flashed after the crash, Windows boots, all
of GIO0/I2C2/QGP0/PEP0 healthy, SPI4 a Disconnected phantom, qcspi service absent.
v30 is the current stable baseline with GPIO + I2C up.

### Binary homework verdict (no-device session): touch is platform-power-blocked

Confirmed by reading the binaries directly:

| driver | PoFx perf-state imports | works on pipa? |
|---|---|---|
| `qci2c_i.sys` (pipa, from stable checkpoint) | **none** — only `PoRegisterPowerSettingCallback` | ✅ Started |
| `qcgpio8250.sys` | none relevant | ✅ Started |
| `qcspi8250.sys` (pipa attempt) | `PoFxRegisterComponentPerfStates` + Issue + Query | ✗ 0xA0 |
| `qcspi8150.sys` (nabu) | **same 3 PoFx perf-state imports** | (works on nabu only) |

Two things are now certain:

1. **The crash mechanism is qcspi's unconditional PoFx perf-state registration.** qci2c and
   qcgpio never call it, which is exactly why they start on pipa's minimal ACPI; qcspi always
   calls it and there is **no registry/INF/ACPI knob in the binary to gate it** (the only
   power strings in qcspi8250.sys are those 3 imports — nothing to disable them).
2. **Swapping qcspi binaries does not help** — nabu's 8150 build registers the same perf
   states. nabu succeeds because nabu boots the *complete Qualcomm OEM ACPI + PEP stack*
   (`PLATFORM.SOC_QC8150.BASE` ships `qcpep8150.sys`, `qcpepextension8150.inf` binding
   `ACPI\VEN_QCOM&DEV_0519` and adding a PPM software component, plus full clock/PEP device
   data). pipa runs the Mu-Qcom **minimal** DSDT + the TouchMin SSDT, which has none of that
   device-specific PEP/clock data, so qcpep can't satisfy qcspi's perf-state negotiation and
   the power manager bugchecks `0xA0`.

**Conclusion: SPI touch is blocked behind real platform power management, not behind an ACPI
resource tweak.** Unblocking it means giving qcpep the SE clock/PEP data — i.e. authoring
proper pipa platform ACPI/PEP config (the muold base deliberately omits it) or porting
nabu's PEP stack. That is firmly in the dangerous power-driver class (the project's
qcpmic/qcpep/qcpil guardrail) and is a heavy, multi-step effort with genuine bugcheck risk.

### Strategic pivot recommendation

The two milestones finished this stretch — **I2C2 (keyboard bus, IRQ 635)** and **GIO0
(GPIO controller, qcgpio + GpioClx)** — are exactly the two prerequisites the **keyboard**
needs, and neither the keyboard bus nor the GPIO line touches PoFx perf-states. The
**keyboard (Nanosic 803) custom driver is therefore fully unblocked**, while touch is not.
Recommended next milestone: build the SpbCx (I2C) + VHF keyboard driver per
[KEYBOARD-NANOSIC-ARCH-20260611.md](KEYBOARD-NANOSIC-ARCH-20260611.md) (report descriptors,
GPIO 100 IRQ line, and the libhidconverter frame protocol are already captured) — a
PC-side development effort that needs no risky flashing. Park touch until someone is ready
to take on pipa platform-power ACPI.

### Candidate next steps for touch (deferred / heavy)

1. (zero-risk homework) Pull `qci2c8250.sys` and diff its PoFx imports to confirm the
   perf-state theory; study the nabu (Mi Pad 5) WOA pack — same qcspi family works there
   on top of a fully configured PEP stack — to see what PEP/clock support SPI needs.
2. (cheap discriminator, reversible) Disable the `qcpep` service on a test boot, flash
   v29, retry qcspi: if it then starts (or fails with a polite Code 10 instead of
   bugchecking), qcpep is confirmed as the crashing component. Needs care — qcpep has
   been running since v19 and its absence may change idle/power behaviour.
3. (heavy) Bring up a real PEP configuration for the SE clock domains (nabu-style) —
   the "proper" fix, but firmly in the dangerous power-class territory.
