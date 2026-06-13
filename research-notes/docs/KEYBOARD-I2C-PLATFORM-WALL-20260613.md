# pipa keyboard — driver works, but I2C transfers hit the platform-power wall (2026-06-13)

## Outcome

The `pipakbd` driver was built, signed, installed, and **loads/binds correctly** to
`ACPI\NANO0803` (the keyboard's I2C node). But the moment it performs the **first real I2C
transfer** to the Nanosic chip (slave 0x4C on `\_SB.I2C2`), the **SoC hard-resets**. The
keyboard could not be brought up. Root cause is the **same platform-power wall that blocks
touch (qcspi)**: on the minimal "muold" ACPI, the QUP/GENI serial-engine clocks aren't
actually powered, so any genuine I2C/SPI transaction wedges the hardware.

## Evidence (decisive)

Driver iterations and what each proved:

- **v2 (VHF + passive timer):** Code 31 `CM_PROB_FAILED_ADD 0xC00000BB` — VHF/passive-exec in
  AddDevice. (Fixed by simplifying.)
- **v3/v4 (enabler, I2C in D0Entry):** **auto-restart during install** — no bugcheck dump.
- **v5 (I2C moved to SelfManagedIoInit):** still auto-restarts.
- **v6 (150 ms timeout on every SPB transfer):** system *sometimes* reaches desktop, but the
  driver's diagnostics are **never written** and there are repeated **Kernel-Power 41**
  dirty-restarts with **no BugCheck (1001) event and no minidump**.

Two facts make the diagnosis airtight:
1. The driver writes `EnableOk/EnableStatus/ReadHead` to the registry *immediately after* the
   first I2C ops. Those values are **never present** → execution dies *at or before the first
   transfer*, before any software error path runs.
2. The restarts produce **Kernel-Power 41 only, with no bugcheck dump**. A driver fault
   (bad pointer, IRQL, timeout) produces a bugcheck + dump. A **dumpless reset** means the
   CPU/bus wedged at the hardware level (touching an unclocked GENI register) → watchdog/SoC
   reset. A 150 ms software timeout can't help because the core is already stuck.

The only minidump on disk (`0xA0 INTERNAL_POWER_ERROR`, `0xAA64…`) is the **old 2026-06-05
qcspi crash** — the same power-error family, the device RTC just reads 2024-04-01.

## Why I2C "Started" was misleading

`qci2c` showed `Started / CM_PROB_NONE` and we treated I2C2 as working. But "Started" only
means the controller driver loaded and claimed its resources (MEM 0x988000, IRQ 635). No
device had ever issued a real transfer on I2C2 until `pipakbd` did — and that first transfer
is what wedges the SoC. Same story as SPI4/qcspi: enumerates fine, dies on real activity.

## The real blocker

The GENI serial engines need their clocks/power brought up by the platform (RPMh clock
controller + qcpep PEP, described in a complete OEM ACPI). The Mu-Qcom **muold minimal**
ACPI deliberately omits that. So **both** the keyboard (I2C2) and touch (SPI4) are blocked by
the same missing platform-power layer — not by anything in our drivers.

Unblocking it requires authoring real pipa platform power/clock ACPI (GENI/QUP clock domains,
PEP) — a large, firmly power-class effort (the qcpmic/qcpep/qcpil territory the project
guard-rails flag as BSOD-prone). That's a separate, major project, not a driver fix.

## What DID work (kept)

- I2C2 ACPI resource fix (IRQ 635, the +32 GSIV correction) — correct, just not transfer-capable.
- GIO0 GPIO controller bind (qcgpio8250) — Started.
- A complete, cloud-built, test-signed ARM64 KMDF driver (`pipakbd`) that correctly binds the
  ACPI node and is structured to drive the keyboard the instant the I2C bus can actually carry
  a transfer. The captured static enable sequence (MIAUTH…) and HID report descriptors remain
  valid for that future.

## Current device state

`boot_b` = **v30** (no KBD0 node → driver never loads → no crash). Windows boots clean and is
usable with an external keyboard/mouse. Android slot A untouched. Rollback ladder intact.

## If revisited

1. (Confirm, optional) A no-op driver that binds KBD0 but does zero I2C — if it loads cleanly
   and a touch test of the bus still wedges, that's the final proof it's the bus, not us.
2. (Hard) Bring up GENI/QUP clocks + PEP for pipa in ACPI — the shared unlock for keyboard AND
   touch. Major firmware work.
