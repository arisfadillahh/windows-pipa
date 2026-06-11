# pipa keyboard (Nanosic 803) — architecture verdict from Android probe (2026-06-11)

Probed the live Android stack (temp-root) on the now-working I2C2 bus to decide the
Windows driver strategy for the magnetic-pogo keyboard cover. **Result: the keyboard is
NOT a standard HID-over-I2C device. The HID layer is synthesized in Xiaomi userspace
software, not emitted by the chip.** This rules out the "easy" ACPI `hidi2c.sys` child.

## The Android stack (what actually makes the keyboard work)

```
TLMM/GPIO + I2C2 (SE 0x988000, slave 0x4C)
        │  proprietary 16-byte frame protocol (NOT HID-over-I2C)
        ▼
kernel  nanosic,803  i2c driver  ──►  /dev/nanodev0   (char dev 479,0; raw frames)
        │   e.g. dmesg: write cmd -> [32004F31803831064D494155544837]
        │                _rawdata_ -> [570F39...]
        ▼
user    vendor.xiaomi.hardware.keyboardnanoapp@1.0-service  (HIDL)
        │   reads nanodev0, parses Nanosic frames
        ▼
        libhidconverter.so  ── GenerateHIDKeyboardData() / GenerateHIDMouseData()
        │                      GenerateHIDTouchPadData()  → _HIDINJECTOR_INPUT_REPORT
        │                      (std::map<string,HID_USAGE_ID> keycode table)
        ▼
        uhid  →  4 virtual HID devices on BUS_VIRTUAL (0x06), VID 0x15D9:
                 00A3 Keyboard | 00A2 Mouse | 00A1 Touch(pad) | 00A4 Consumer
```

Evidence the descriptors are software-synthesized (not read from the chip):

- `libhidconverter.so` exports `GenerateHIDKeyboardData`, `GenerateHIDMouseData`,
  `GenerateHIDTouchPadData` returning a `_HIDINJECTOR_INPUT_REPORT`, plus a
  `std::map<std::string, HID_USAGE_ID>` (key-name → usage lookup). The HID reports are
  *built in code*.
- The 4 HID devices enumerate on **bus 0x06 = BUS_VIRTUAL** (uhid), bound to
  `hid-generic` / `hid-multitouch` — i.e. injected by userspace, not a kernel i2c-hid bus.
- The kernel exposes only `/dev/nanodev0` (raw) + sysfs knobs `_gpioset`, `_keycode`,
  `_debuglevel`. There is no HID descriptor register on the device.

So the chip speaks a **vendor frame protocol** over I2C; "HID" exists only above it in
Xiaomi's HAL.

## Captured HID report descriptors (the Windows interface contract)

These are exact and reusable by whatever Windows path we pick (e.g. a VHF descriptor).

| Collection | VID:PID | Bytes | Usage page | Report ID | Shape |
|---|---|---|---|---|---|
| Keyboard | 15D9:00A3 | 61 | Generic Desktop → Keyboard/Keypad + LED | 5 | 8 modifier bits + 1 const + 5 LED out + 6×8-bit keys (max 0xA4) |
| Mouse | 15D9:00A2 | 56 | Generic Desktop (Pointer) + Button | 2 | 5 buttons + 3 const + X/Y/Wheel 16-bit |
| Touch(pad) | 15D9:00A1 | 260 | Digitizer + Button + Generic Desktop | 25 | multitouch (hid-multitouch bound) |
| Consumer | 15D9:00A4 | 25 | Consumer | 6 | 1×16-bit usage, 0x00..0x380 |

(Raw `.bin`/`.hex` kept locally; not committed — they are the device interface, small.)

## GPIO / pin map (from DT `nanosic@4c`, TLMM GPIO numbers)

| Function | TLMM GPIO | Notes |
|---|---|---|
| **irq** | **100** | flags 0x6001 — keyboard attention/interrupt line. This is the GpioInt a Windows driver needs. |
| reset | 141 | |
| sleep | 155 | |
| status | 46 | |
| vdd (power en) | 127 | |
| hall_n / hall_s | 110 / 121 | lid/fold hall sensors |

The IRQ on GPIO 100 means a Windows driver also needs a **working GPIO controller**
(`GIO0`) to receive the attention interrupt — currently GIO0 is bound to the GenPass
stub, so it is not yet a functional `GpioClx` controller. This couples the keyboard to
the GPIO milestone.

## Windows strategy implications

- **ACPI `hidi2c.sys` child (the normal HID-over-I2C path): NOT viable** — the chip has
  no HID descriptor register; a standard child would read garbage. Do **not** build a
  v26 that just adds an `_HID`/HID-descriptor `_DSM` child for slave 0x4C expecting HID.
- **Viable path = custom Windows driver** mirroring Android: an SpbCx (I2C) client that
  speaks the Nanosic frame protocol, plus Microsoft **VHF (Virtual HID Framework)** to
  present the 4 collections above. The libhidconverter `GenerateHID*` logic and the frame
  protocol (from the nanodev kernel driver) would need to be reverse-engineered/ported.
  All inputs for this are now captured: exact report descriptors, GPIO map, I2C address,
  and the 23 KB `libhidconverter.so` with intact symbols.
- This is a multi-week driver-development effort, not an ACPI tweak. It should be weighed
  against doing **touch (Novatek NT36532 on SPI4)** first, which is a more conventional
  target (existing WOA NVT drivers may apply) — though touch is currently blocked on the
  SPI4 IRQ (needs 637) and the unexplained "SEC5/TCHMIN replacement kills display" issue.

## Bottom line

The I2C2 bus fix (v25) was the right and necessary first step, but the keyboard cannot be
finished with ACPI alone — it needs a custom HID driver. The probe's value: it eliminated
a dead-end build and captured the complete blueprint (descriptors + pin map + protocol
source) for the real path.

## Driver-source homework (2026-06-11, no-device): the build is now de-risked

Two findings sharpen the layering and remove the biggest unknown:

1. **`libhidconverter.so` is HID-mapping only, not the chip protocol.** Its exports take
   *already-parsed* input — `GenerateHIDKeyboardData(mods, vector<KEYCODE_string>, report)`,
   `GenerateHIDMouseData(buttons, dx, dy, wheel, report)`,
   `GenerateHIDTouchPadData(...)` — and look each Android `KEYCODE_*` up in a
   `std::map<string, HID_USAGE_ID>` (119 KEYCODE tokens extracted). So this layer is trivially
   re-derivable from the report descriptors we already captured; it is **not** where the
   Nanosic frame protocol lives.

2. **The frame protocol is open-source GPL kernel code.** The chip's 16-byte I2C frame
   protocol (the `32004F31…` command / `570F39…` response seen in dmesg) is implemented in
   Xiaomi's published pipa kernel:
   `MiCode/Xiaomi_Kernel_OpenSource`, branch **`pipa-t-oss`**,
   `drivers/input/keyboard/nanosic_driver/` (and `nanosic_driver_v2/`):
   - `nano_i2c.c` — I2C read/write framing (the protocol to port)
   - `nano_macro.h` — opcodes / frame constants
   - `nano_input.c` / `nano_input.h` — frame → input-event decode
   - `nano_gpio.c` — the GPIO 100 attention-IRQ + reset/power line handling
   - `nano_chardev.c` — the `/dev/nanodev0` interface the HAL reads
   This is readable, license-clear reference — the Windows driver can mirror its framing
   logic directly rather than black-box reverse-engineering the binary.

### Windows driver shape (now fully specified)

- **SpbCx I2C target** on `\_SB.I2C2` (✅ bus up, IRQ 635), slave `0x4C`.
- **GpioInt** on `\_SB.GIO0` (✅ GpioClx up), TLMM GPIO **100** = attention line; plus
  reset/vdd/sleep GPIOs (141 / 127 / 155) toggled per `nano_gpio.c`.
- **Frame engine** ported from `nano_i2c.c` + `nano_macro.h`.
- **Microsoft VHF** presenting the 4 captured collections (keyboard / mouse / touchpad /
  consumer) using the exact report descriptors in `research-notes/keyboard-hid/`.
- Packaged as a KMDF driver; needs an EWDK/WDK build environment and on-device iteration.
  No PoFx perf-states involved, so it is **not** subject to the qcpep wall that blocks touch.

This is the recommended next milestone (touch is parked behind platform power). Remaining
prerequisite to start coding: a Windows driver toolchain (EWDK or WDK + VS).
