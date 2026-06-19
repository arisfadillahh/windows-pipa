/*
 * NanoKbdSSDT.asl - ACPI child node for the Nanosic 803 keyboard under I2C2.
 *
 * Adds \_SB.I2C2.KBD0 (_HID NANO0803) so Windows enumerates ACPI\NANO0803 and binds
 * pipakbd.sys. Resources:
 *   - I2cSerialBusV2 slave 0x4C on \_SB.I2C2 (the working keyboard bus, IRQ 635)
 *   - GpioIo on \_SB.GIO0 pins reset/vdd/sleep = 141/127/155
 *
 * I2C speed: 400 kHz assumed (fast mode). The GPIO resource is output-only:
 * the driver powers the chip and polls over I2C; it does not use the attention IRQ yet.
 */
DefinitionBlock ("", "SSDT", 2, "PIPA", "NANOKBD", 0x00000002)
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
            Name (_DEP, Package (0x01) { \_SB.GIO0 })
            Method (_STA, 0, NotSerialized) { Return (0x0F) }

            Method (_CRS, 0, Serialized)
            {
                Name (RBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x004C, ControllerInitiated, 0x00061A80,
                        AddressingMode7Bit, "\\_SB.I2C2",
                        0x00, ResourceConsumer, , Exclusive, )

                    // Pin order is reset, vdd, sleep. pipakbd writes bit 0/1/2 in this order.
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000,
                        IoRestrictionOutputOnly, "\\_SB.GIO0", 0x00,
                        ResourceConsumer, , )
                        { 0x008D, 0x007F, 0x009B }
                })
                Return (RBUF)
            }
        }
    }
}
