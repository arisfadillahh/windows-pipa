// frame.c - Nanosic 803 frame parser.
//
// This is a direct port of the read/dispatch logic in the GPL kernel driver
// (MiCode/Xiaomi_Kernel_OpenSource, pipa-t-oss,
//  drivers/input/keyboard/nanosic_driver_v2/nano_i2c.c :: Nanosic_i2c_parse).
// SPDX-License-Identifier: GPL-2.0  (derived from GPL-2.0 kernel source)
//
// Frame layout of a 68-byte I2C read from slave 0x4C:
//   buf[0] = 0x57            (magic; discard frame otherwise)
//   buf[1] = sequence
//   buf[2] = group in {0x39,0x4A,0x5B,0x6C}  (0x00 => null/no data)
//   buf[3..] = stream of sub-packets; each sub-packet's first byte is its HID Report ID
//              and the whole fixed-length slice IS a ready HID input report.
//
// The chip already produces HID-formatted reports, so each slice is handed to VHF as-is.

#include "pipakbd.h"

VOID
PipaKbd_ParseFrame(
    _In_ PDEVICE_CONTEXT Ctx,
    _In_reads_(Len) const UCHAR* Buf,
    _In_ ULONG Len)
{
    if (Len < 3)                       return;
    if (Buf[0] != NANO_FRAME_MAGIC)    return;     // first_byte != 0x57
    // Buf[1] = seq (unused here)
    if (Buf[2] == 0x00)                return;     // null packet
    if (!NANO_GROUP_IS_VALID(Buf[2]))  return;     // unknown group

    ULONG i = 3;                                   // sub-packet stream start
    while (i < Len) {
        UCHAR type = Buf[i];                       // == HID Report ID
        ULONG slice;

        switch (type) {
        case NANO_T_KEYBOARD: slice = NANO_L_KEYBOARD; break;   // 9
        case NANO_T_CONSUMER: slice = NANO_L_CONSUMER; break;   // 5
        case NANO_T_MOUSE:    slice = NANO_L_MOUSE;    break;   // 8
        case NANO_T_TOUCH:    slice = NANO_L_TOUCH;    break;   // 21

        // Vendor/diagnostic frames: Android forwards these to /dev/nanodev0 for the
        // userspace HAL. This HID driver does not implement the vendor channel, so we
        // skip the known fixed-size ones and stop on the rest-of-buffer variants.
        case NANO_T_VENDOR16: slice = 16; goto skip;
        case NANO_T_VENDOR32: slice = 32; goto skip;
        case NANO_T_VENDOR_REST_A:
        case NANO_T_VENDOR_REST_B:
            return;                                 // consumes remainder; nothing for HID
        default:
            return;                                 // unknown -> stop (kernel sets left=0)
        skip:
            if (i + slice > Len) return;
            i += slice;
            continue;
        }

        if (i + slice > Len) return;                // truncated; bail
        // The slice [type .. ] is a complete HID input report (report id = type).
        PipaKbd_VhfSubmitReport(Ctx, &Buf[i], slice);
        i += slice;
    }
}
