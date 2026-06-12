// pipakbd.h - shared definitions for the pipa Nanosic 803 HID-over-I2C VHF driver.
#pragma once

#include <ntddk.h>
#include <wdf.h>
#include <ntstrsafe.h>  // RtlStringCchPrintfW (resource-hub path)
#include <reshub.h>     // RESOURCE_HUB_PATH_SIZE, RESOURCE_HUB_DEVICE_NAME_PREFIX
#include <SPBCx.h>
#include <gpio.h>
#include <hidport.h>    // HID_XFER_PACKET
#include <vhf.h>

//
// Recent WDK reshub.h refactored RESOURCE_HUB_CREATE_PATH_FROM_ID out. Provide the classic
// macro when absent, built from parts that are still present. Produces the standard
// resource-hub path "\Device\RESOURCE_HUB\<16-hex connection id>".
//
#ifndef RESOURCE_HUB_CREATE_PATH_FROM_ID
#define RESOURCE_HUB_CREATE_PATH_FROM_ID(Path, LowPart, HighPart)                  \
{                                                                                  \
    (VOID) RtlStringCchPrintfW(                                                    \
        (Path)->Buffer,                                                            \
        (Path)->MaximumLength / sizeof(WCHAR),                                     \
        L"%ws%0*I64x",                                                             \
        RESOURCE_HUB_DEVICE_NAME_PREFIX,                                           \
        16,                                                                        \
        (((ULONGLONG)(HighPart)) << 32) | (ULONGLONG)(ULONG)(LowPart));            \
    RtlInitUnicodeString((Path), (Path)->Buffer);                                  \
}
#endif

//
// Nanosic 803 protocol constants (mirrored from the GPL kernel driver:
// MiCode/Xiaomi_Kernel_OpenSource, branch pipa-t-oss,
// drivers/input/keyboard/nanosic_driver_v2/{nano_macro.h,nano_i2c.c}).
//
#define NANO_I2C_SLAVE_ADDR     0x4C        // 7-bit
#define NANO_READ_LEN           68          // I2C_DATA_LENGTH_READ
#define NANO_WRITE_LEN          66          // I2C_DATA_LENGTH_WRITE
#define NANO_FRAME_MAGIC        0x57        // buf[0] (first_byte), else discard
// buf[2] (third_byte) packet-group whitelist; 0x00 = null packet
#define NANO_GROUP_IS_VALID(g)  ((g)==0x39 || (g)==0x4A || (g)==0x5B || (g)==0x6C)

// Sub-packet type byte (== HID Report ID) and its on-wire slice length (incl. the type byte).
#define NANO_T_KEYBOARD 0x05
#define NANO_L_KEYBOARD 9
#define NANO_T_CONSUMER 0x06
#define NANO_L_CONSUMER 5
#define NANO_T_MOUSE    0x02
#define NANO_L_MOUSE    8
#define NANO_T_TOUCH    0x19
#define NANO_L_TOUCH    21
// Vendor/diagnostic sub-packets (forwarded to userspace on Android; ignored here).
#define NANO_T_VENDOR16 0x22   // 16 bytes
#define NANO_T_VENDOR32 0x23   // 32 bytes
#define NANO_T_VENDOR_REST_A 0x24
#define NANO_T_VENDOR_REST_B 0x26

typedef struct _DEVICE_CONTEXT {
    WDFDEVICE           Device;

    // SpbCx (I2C2) target opened from the ACPI I2cSerialBus connection resource.
    WDFIOTARGET         SpbTarget;
    LARGE_INTEGER       SpbConnectionId;

    // GpioInt attention line (TLMM GPIO 100) opened from the second ACPI resource.
    WDFINTERRUPT        Interrupt;

    // Microsoft Virtual HID Framework handle.
    VHFHANDLE           VhfHandle;
    BOOLEAN             VhfStarted;

    // Bounce buffer for one 68-byte I2C read, filled in the DPC.
    UCHAR               ReadBuffer[NANO_READ_LEN];
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

// device.c
EVT_WDF_DRIVER_DEVICE_ADD        PipaKbdEvtDeviceAdd;
EVT_WDF_DEVICE_PREPARE_HARDWARE  PipaKbdEvtPrepareHardware;
EVT_WDF_DEVICE_RELEASE_HARDWARE  PipaKbdEvtReleaseHardware;
EVT_WDF_DEVICE_D0_ENTRY          PipaKbdEvtD0Entry;
EVT_WDF_DEVICE_D0_EXIT           PipaKbdEvtD0Exit;
EVT_WDF_INTERRUPT_ISR            PipaKbdEvtInterruptIsr;
EVT_WDF_INTERRUPT_DPC            PipaKbdEvtInterruptDpc;

// spb.c
NTSTATUS PipaKbd_SpbReadFrame(_In_ PDEVICE_CONTEXT Ctx);
NTSTATUS PipaKbd_SpbWrite(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Data, _In_ ULONG Len);

// frame.c
VOID     PipaKbd_ParseFrame(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Buf, _In_ ULONG Len);

// vhf.c
NTSTATUS PipaKbd_VhfCreate(_In_ PDEVICE_CONTEXT Ctx);
VOID     PipaKbd_VhfDestroy(_In_ PDEVICE_CONTEXT Ctx);
VOID     PipaKbd_VhfSubmitReport(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Report, _In_ ULONG Len);
