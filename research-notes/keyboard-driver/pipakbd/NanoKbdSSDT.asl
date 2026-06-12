/*
 * NanoKbdSSDT.asl - ACPI child node for the Nanosic 803 keyboard under I2C2.
 *
 * Adds \_SB.I2C2.KBD0 (_HID NANO0803) so Windows enumerates ACPI\NANO0803 and binds
 * pipakbd.sys. Resources:
 *   - I2cSerialBusV2 slave 0x4C on \_SB.I2C2 (the working keyboard bus, IRQ 635)
 *   - GpioInt on \_SB.GIO0 pin 100 (TLMM GPIO 100 = the chip attention line)
 *
 * Build/flash: compile with iasl, append as a new ACPI section (e.g. SEC8) exactly like
 * the append-only I2C2 SSDT pattern in codex-repack-v25/v29, producing a v31 image. This
 * is the ONLY device-side change pipakbd needs; it does not touch GIO0/I2C2/SPI4, so the
 * v29/v30 baseline behaviour is preserved (rollback ladder unchanged).
 *
 * I2C speed: 400 kHz assumed (fast mode). Confirm against nano_i2c.c board_info if the
 * chip NAKs at 400k; drop to 100k otherwise.
 */
DefinitionBlock ("", "SSDT", 2, "PIPA", "NANOKBD", 0x00000001)
{
    External (\_SB.I2C2, DeviceObj)
    External (\_SB.GIO0, DeviceObj)

    Scope (\_SB.I2C2)
    {
        Device (KBD0)
        {
            Name (_HID, "NANO0803")
            Name (_UID, Zero)
            Name (_DDN, "Xiaomi Pad 6 Keyboard (Nanosic 803)")
            Method (_STA, 0, NotSerialized) { Return (0x0F) }

            // I2C-only: no GpioInt. A GpioInt on GIO0 caused STATUS_DEVICE_POWER_FAILURE
            // (Code 10) at ACPI bring-up — GIO0's interrupt delivery isn't usable. The driver
            // polls the chip over I2C instead, so no interrupt resource is declared.
            Method (_CRS, 0, Serialized)
            {
                Name (RBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x004C, ControllerInitiated, 0x00061A80,
                        AddressingMode7Bit, "\\_SB.I2C2",
                        0x00, ResourceConsumer, , Exclusive, )
                })
                Return (RBUF)
            }
        }
    }
}
