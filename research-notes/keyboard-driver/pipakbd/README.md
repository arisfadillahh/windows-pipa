# pipakbd — Xiaomi Pad 6 (pipa) keyboard driver for Windows on ARM

Custom KMDF driver that brings up the magnetic pogo keyboard (Nanosic **803**, I2C slave
`0x4C` on `\_SB.I2C2`) as a HID device on WOA, by mirroring the Android kernel driver's
frame protocol and re-presenting it through the Microsoft **Virtual HID Framework (VHF)**.

This is a **source scaffold** — authored from captured device facts and the public GPL
kernel source. It has **not** been compiled or run yet (needs a WDK/EWDK toolchain and
on-device iteration). Everything device-specific is grounded in real data, not guessed.

## Why this approach

The chip is **not** standard HID-over-I2C — there is no HID descriptor register, so the
in-box `hidi2c.sys` cannot drive it. On Android the stack is:

```
Nanosic 803 (I2C 0x4C) --frames--> kernel nanosic_driver --> hid_input_report --> uhid
```

Key discovery (see `../docs/KEYBOARD-NANOSIC-ARCH-20260611.md`): the **v2 kernel driver
passes the chip payload straight into `hid_input_report`** — i.e. the chip already emits
HID-formatted reports. So this Windows driver is a thin pass-through: read frame → slice
sub-packets → submit to VHF. No keycode translation (that lives only in the userspace
`libhidconverter`, which this driver does not need).

Crucially, this path uses **no PoFx perf-states**, so it is *not* blocked by the qcpep
power wall that blocks the SPI touch controller.

## Protocol (mirrored from GPL kernel source)

Source of truth: `MiCode/Xiaomi_Kernel_OpenSource`, branch `pipa-t-oss`,
`drivers/input/keyboard/nanosic_driver_v2/` (`nano_macro.h`, `nano_i2c.c`, `nano_input.c`).

- Attention IRQ (TLMM **GPIO 100**, active-low) → read **68 bytes** from slave `0x4C`.
- Frame: `[0]=0x57` magic, `[1]=seq`, `[2]∈{0x39,0x4A,0x5B,0x6C}` (`0x00`=null).
- Then sub-packets; **first byte = HID Report ID**, whole slice = a ready HID report:

  | type/ReportID | meaning  | slice len | HID collection (VID 0x15D9) |
  |---|---|---|---|
  | `0x05` | keyboard | 9  | PID 0x00A3 |
  | `0x02` | mouse    | 8  | PID 0x00A2 |
  | `0x06` | consumer | 5  | PID 0x00A4 |
  | `0x19` | touchpad | 21 | PID 0x00A1 |
  | `0x22/0x23/0x24/0x26` | vendor/diag | 16/32/rest | (Android userspace only; skipped) |

`report_descriptor.h` is the four captured collections concatenated (402 bytes); reports
route by the unique Report IDs above.

## Files

| file | role |
|---|---|
| `driver.c` | DriverEntry, device add, interrupt object |
| `device.c` | resource parse (I2C conn-id + GpioInt), D0 entry/exit, ISR/DPC |
| `spb.c` | SpbCx I2C 68-byte read + write helper |
| `frame.c` | **frame parser** (GPL-derived port of `nano_i2c.c` dispatch) |
| `vhf.c` | VHF create/start + report submit (pass-through) |
| `report_descriptor.h` | combined HID report descriptor (captured) |
| `pipakbd.inf` | install, binds `ACPI\NANO0803`, KMDF + VHF |
| `NanoKbdSSDT.asl` | ACPI child `\_SB.I2C2.KBD0` (I2cSerialBus 0x4C + GpioInt 100) |
| `pipakbd.vcxproj` | EWDK/MSBuild project |

## Build (no device needed)

Needs the **EWDK** (Enterprise WDK ISO; self-contained, no VS install) or WDK + Visual Studio.

```
# from an EWDK LaunchBuildEnv prompt:
msbuild pipakbd.vcxproj /p:Configuration=Release /p:Platform=ARM64
```

Output: `pipakbd.sys` + `pipakbd.inf` (+ cat after `inf2cat`/test-signing).

## Integrate + test (needs device)

1. **ACPI**: compile `NanoKbdSSDT.asl` (`iasl NanoKbdSSDT.asl`) and append it as a new
   ACPI section (SEC8) using the established append-only repack (clone
   `codex-repack-v29-…ps1`, add a SEC8 step) → produce **v31**. This is the only firmware
   change; GIO0/I2C2/SPI4 are untouched, so the v29/v30 rollback ladder still applies.
2. Enable test-signing on the WOA install (`bcdedit /set testsigning on`), install the
   driver (`pnputil /add-driver pipakbd.inf /install`), flash v31, boot.
3. `pnputil /enum-devices /instanceid ACPI\NANO0803\0` should show **Started**; press keys
   and watch input. Use the `fix-*`-style staged cmd + the boot-telemetry net for capture.
4. Rollback if it misbehaves: driver is DEMAND_START and PoFx-free (low bootloop risk);
   worst case `pnputil /delete-driver` offline + flash back v30.

## Open TODOs (verify on hardware)

- **Init handshake**: `device.c` D0Entry has a TODO to replay the chip's startup write(s)
  before it streams (observed host→chip write starts `0x32 0x00 0x4F 0x31 …`). Lift the
  exact 66-byte write sequence from `nano_driver.c`/`nano_i2c.c` (`Nanosic_i2c_write`).
- **Touch report shape**: the 21-byte touch slice vs the 260-byte digitizer descriptor —
  confirm it matches one input report (it should; descriptor has report-id 25 input only).
- **I2C clock**: 400 kHz assumed in the SSDT; confirm against board_info.
- **GPIO aux lines**: reset/vdd/sleep (GPIO 141/127/155) — the chip may already be powered
  by firmware; add explicit GPIO toggling (a second GpioIo resource + `nano_gpio.c` logic)
  only if the device doesn't respond.

## Provenance / licensing

`frame.c` and the protocol constants are derived from GPL-2.0 kernel source (Xiaomi
`pipa-t-oss`); treat the driver as **GPL-2.0**. The report descriptors were read from the
device's own HID interface. No proprietary Xiaomi binaries are included or required.
