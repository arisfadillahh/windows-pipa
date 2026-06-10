# pipa WOA — v19 live dump analysis: root cause of I2C2/GIO0 Code 12 (2026-06-10)

## Summary

The v19 baseline live PnP dump plus offline analysis of the v19 ACPI tables and the Android
device tree identified the root cause of the `CM_PROB_NORMAL_CONFLICT` (Code 12,
`0xC0000018 {Conflicting Address Range}`) on the I2C2 keyboard bus controller:

**The I2C2 SSDT declared the raw device-tree hwirq (603) instead of the Windows ACPI
GSIV (hwirq + 32 = 635).** The same raw value 603 also appears in a junk shared-IRQ list
inside the stock `TCHMIN` SSDT's `GIO0` device, so the two devices collided on a vector
that is wrong for both.

## Evidence

### v19 device state (live dump, Get-PnpDevice + pnputil)

| Device | _HID (loc) | Status | Notes |
|---|---|---|---|
| `ACPI\QCOM0511\2` (`\_SB.I2C2`) | QCOM0511/_CID QCOM2511 | Code 12, 0xC0000018 | qci2c bound (oem3.inf 1.0.2100.0), service RUNNING; MEM 0x988000+0x4000, IRQ 603 |
| `ACPI\QCOM050D\0` (`\_SB.GIO0`) | QCOM050D/_CID QCOMFFE3 | Code 12, 0xC0000018 | bound to Microsoft **genpass.inf** via _CID QCOMFFE3 — not a real GPIO driver; qcgpio service absent |
| `ACPI\QCOM050F\4` (`\_SB.SPI4`) | QCOM050F | Code 28 | no driver installed (qcspi absent); MEM 0x990000, IRQ 605 |
| `ACPI\QCOM0593\0` (`\_SB.QGP0`) | QCOM0593 | **Started, OK** | qcGPI 1.0.1860 RUNNING; MEM 0x904000+0x50000, IRQ 277 |
| `ACPI\QCOM0519` (`\_SB.PEP0`) | QCOM0519/_CID PNP0D80 | Started (raw, `\Driver\ACPI` only) | **no _CRS** — claims nothing; qcpep service RUNNING |
| `ACPI\QCOM2511\2` | QCOM2511 | Disconnected (phantom) | leftover devnode from a previous image variant; driver was configured, which implies that image reached PnP configuration (likely booted with dead display rather than hanging in UEFI) |

### GIO0 _CRS in stock TCHMIN is junk

```
Memory32Fixed 0x0F000000 + 0x01000000          ; whole 16MB TLMM window
Interrupt Level Shared    240, 240, 240        ; TLMM summary (208+32) duplicated 3x
Interrupt Level Shared    578 (0x242)
Interrupt Edge  Shared    603 (0x25B)          ; raw DT hwirq of i2c@988000!
Interrupt Level Shared    601 (0x259)
Interrupt Edge  Exclusive 556 (0x22C)
Interrupt Edge  Exclusive 590 (0x24E)
```

The list mixes +32-converted values (240) with raw DT hwirqs (603 = i2c@988000,
605-adjacent values etc.). I2C2's `Level/Exclusive 603` vs GIO0's `Edge/Shared 603`
is a hard arbiter conflict — mode mismatch and exclusivity mismatch on the same vector.

### The +32 GSIV convention is proven by working devices in the same image

| Device | ACPI vector | Android DT hwirq | Works? |
|---|---|---|---|
| UFS0 | 297 | 265 (GIC_SPI) | yes — Windows boots from UFS |
| QGP0 (GPI DMA @0x900000) | 277 | 244..256 (event rings) | yes — Started/OK |
| I2C2 (i2c@988000) | **603 (wrong)** | 603 → should be **635** | Code 12 |
| SPI4 (spi@990000) | **605 (wrong)** | 605 → should be **637** | (also needs qcspi) |

Android DT ground truth (read from running Android via root):

- `soc/i2c@988000/interrupts = <0 0x25B 0x4>` → GIC SPI 603, level-high → GSIV 635
- `soc/spi@990000/interrupts = <0 0x25D 0x4>` → GIC SPI 605, level-high → GSIV 637
- `soc/qcom,gpi-dma@900000/interrupts` = GIC SPI 244..256 → QGP0's 277 = 245+32 ✓
- `soc/qcom,qup_uart@988000/status = "disabled"` — no UART contention on the keyboard SE

### Android ground truth for input devices

- Keyboard pogo bridge: **Nanosic 803** (`nanosic,803`) at **i2c-1 = SE 0x988000, slave 0x4C**;
  exposes HID collections "Xiaomi Keyboard/Mouse/Touch/Consumer" (VID 0x15D9, PID 0x00A1-0x00A4).
- Touch panel: **Novatek NT36532** (`NVT-ts-spi`) on **spi0 = SE 0x990000** (BUS_SPI, pen supported)
  — matches `SPI4` + `NVTS` (_HID NVT36532) in TCHMIN.

So the I2C2 (0x988000) target choice was correct all along; only the interrupt vector was wrong.

### PEP0 exonerated

`PEP0` (QCOM0519, _CID PNP0D80) has **no _CRS** in TCHMIN — it cannot be the source of the
resource conflicts. It raw-starts on `\Driver\ACPI` only.

## Fix: v25 (append-only, single variable)

`codex-repack-v25-i2c2-irq635-local.ps1` — identical pipeline to v19 (SEC5/TCHMIN untouched,
proven append-only SEC7 pattern). Only change inside the appended SSDT (`I2C2V25`):

```
Interrupt (ResourceConsumer, Level, ActiveHigh, Exclusive) { 0x0000027B }  // 635 = 603+32
```

Verification of the built image: SEC1–SEC5 are byte-identical to the v19 scratch sections;
only SEC7 differs. Instance path stays `ACPI\QCOM0511\2`, so the already-configured qci2c
driver binds without any new driver installation.

Expected outcome: I2C2 devnode starts (Code 12 gone) and the GENI interrupt actually fires
on the correct GIC vector. GIO0 may remain Code 12 (its junk _CRS is a separate, lower
priority issue and it is bound to GenPass anyway).

## Live dump script v2

`live-v19-dump.ps1` (staged on the Windows partition) extended with, all read-only:

- all problem devices (`Get-PnpDevice` non-OK)
- WMI allocated-resource owner maps: every allocated IRQ with its owning device, and
  allocated memory in 0x00900000–0x009FFFFF / 0x0F000000–0x0FFFFFFF
- Kernel-PnP Configuration + System log events filtered for QCOM/conflict

This names the conflicting owner explicitly if any conflict remains after v25.

## Open questions / next steps

1. Flash v25 to boot_b (v19 image kept as rollback), boot Windows, run the v2 dump,
   confirm I2C2 starts and IRQ 635 is allocated to `ACPI\QCOM0511\2`.
2. Next milestone after the bus starts: HID-over-I2C child for the Nanosic 803 at 0x4C
   (needs GpioInt for the alert line → may depend on a working GPIO controller, or
   a custom driver mirroring Android's nanosic/libhidconverter behaviour).
3. SPI4 touch: needs vector 637 (TCHMIN edit — blocked on understanding why every
   SEC5-replacement build (v20–v24) failed to reach the desktop; the configured phantom
   `ACPI\QCOM2511\2` devnode suggests at least v24 booted with a dead display rather
   than hanging in UEFI).
4. GIO0 cleanup (dedupe 240, drop foreign QUP vectors, real qcgpio driver) — later,
   needed for touch GpioInt and keyboard interrupt line.
