// pipakbd.h - shared definitions for the pipa Nanosic 803 HID-over-I2C VHF driver.
#pragma once

#include <ntddk.h>
#include <wdf.h>
#include <ntstrsafe.h>  // RtlStringCchPrintfW (resource-hub path)
#include <reshub.h>     // RESOURCE_HUB_PATH_SIZE, RESOURCE_HUB_DEVICE_NAME_PREFIX
#include <hidport.h>    // HID_XFER_PACKET
#include <vhf.h>

//
// Recent WDK reshub.h refactored RESOURCE_HUB_CREATE_PATH_FROM_ID out. Provide the classic
// macro when absent. Produces "\Device\RESOURCE_HUB\<16-hex connection id>".
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
// Nanosic 803 protocol (mirrored from GPL kernel driver: MiCode/Xiaomi_Kernel_OpenSource
// pipa-t-oss, drivers/input/keyboard/nanosic_driver_v2). The chip uses a 1-byte internal
// address equal to its slave address (const_iaddr_bytes=1): every transfer is prefixed on
// the wire by 0x4C (write) or selected by writing 0x4C before a read.
//
#define NANO_I2C_SLAVE_ADDR     0x4C
#define NANO_IADDR              0x4C        // first data byte on every transfer
#define NANO_READ_LEN           68          // I2C_DATA_LENGTH_READ
#define NANO_FRAME_BYTES        66          // I2C_DATA_LENGTH_WRITE (command payload)

// Frame parser constants (read path).
#define NANO_FRAME_MAGIC        0x57
#define NANO_GROUP_IS_VALID(g)  ((g)==0x39 || (g)==0x4A || (g)==0x5B || (g)==0x6C)
#define NANO_T_KEYBOARD 0x05
#define NANO_L_KEYBOARD 9
#define NANO_T_CONSUMER 0x06
#define NANO_L_CONSUMER 5
#define NANO_T_MOUSE    0x02
#define NANO_L_MOUSE    8
#define NANO_T_TOUCH    0x19
#define NANO_L_TOUCH    21
#define NANO_T_VENDOR16 0x22
#define NANO_T_VENDOR32 0x23
#define NANO_T_VENDOR_REST_A 0x24
#define NANO_T_VENDOR_REST_B 0x26

#define NANO_POLL_MS    15                  // I2C key-frame poll interval

typedef struct _DEVICE_CONTEXT {
    WDFDEVICE           Device;
    WDFIOTARGET         SpbTarget;          // I2C2 controller (slave 0x4C) via ACPI conn-id
    LARGE_INTEGER       SpbConnectionId;
    WDFTIMER            PollTimer;          // passive-level periodic I2C read
    VHFHANDLE           VhfHandle;
    BOOLEAN             VhfStarted;
    UCHAR               ReadBuffer[NANO_READ_LEN];
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

// device.c
EVT_WDF_DRIVER_DEVICE_ADD        PipaKbdEvtDeviceAdd;
EVT_WDF_DEVICE_PREPARE_HARDWARE  PipaKbdEvtPrepareHardware;
EVT_WDF_DEVICE_RELEASE_HARDWARE  PipaKbdEvtReleaseHardware;
EVT_WDF_DEVICE_D0_ENTRY          PipaKbdEvtD0Entry;
EVT_WDF_DEVICE_D0_EXIT           PipaKbdEvtD0Exit;
EVT_WDF_TIMER                    PipaKbdEvtPollTimer;

// spb.c
NTSTATUS PipaKbd_SpbWriteFrame(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Frame, _In_ ULONG Len);
NTSTATUS PipaKbd_SpbReadFrame(_In_ PDEVICE_CONTEXT Ctx);
NTSTATUS PipaKbd_SendEnableSequence(_In_ PDEVICE_CONTEXT Ctx);

// frame.c
VOID     PipaKbd_ParseFrame(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Buf, _In_ ULONG Len);

// vhf.c
NTSTATUS PipaKbd_VhfCreate(_In_ PDEVICE_CONTEXT Ctx);
VOID     PipaKbd_VhfDestroy(_In_ PDEVICE_CONTEXT Ctx);
VOID     PipaKbd_VhfSubmitReport(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Report, _In_ ULONG Len);
