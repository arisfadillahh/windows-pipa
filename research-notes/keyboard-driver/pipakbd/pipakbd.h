// pipakbd.h - Nanosic 803 keyboard "enabler" driver.
//
// The keyboard's keystrokes arrive over the separate USB HID device (Sino Wealth
// VID_258A&PID_008A, which Windows already drives with inbox HID). They only start flowing
// after the Nanosic 803 control chip is unlocked via a fixed I2C enable/auth sequence
// (captured from the Android HAL). This driver binds the ACPI I2C node (ACPI\NANO0803) and
// does exactly one thing: replay that enable sequence at D0Entry. No VHF, no polling.
#pragma once

#include <ntddk.h>
#include <wdf.h>
#include <ntstrsafe.h>  // RtlStringCchPrintfW
#include <reshub.h>     // RESOURCE_HUB_PATH_SIZE, RESOURCE_HUB_DEVICE_NAME_PREFIX

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

// Chip uses a 1-byte internal address equal to its slave address (const_iaddr_bytes=1):
// every write is prefixed on the wire by 0x4C.
#define NANO_IADDR              0x4C
#define NANO_FRAME_BYTES        66          // I2C_DATA_LENGTH_WRITE command payload

#define NANO_READ_LEN   68

typedef struct _DEVICE_CONTEXT {
    WDFDEVICE       Device;
    WDFIOTARGET     SpbTarget;
    LARGE_INTEGER   SpbConnectionId;
    UCHAR           ReadBuffer[NANO_READ_LEN];
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

EVT_WDF_DRIVER_DEVICE_ADD        PipaKbdEvtDeviceAdd;
EVT_WDF_DEVICE_PREPARE_HARDWARE  PipaKbdEvtPrepareHardware;
EVT_WDF_DEVICE_RELEASE_HARDWARE  PipaKbdEvtReleaseHardware;
EVT_WDF_DEVICE_D0_ENTRY          PipaKbdEvtD0Entry;
EVT_WDF_DEVICE_D0_EXIT           PipaKbdEvtD0Exit;

NTSTATUS PipaKbd_SpbWriteFrame(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Frame, _In_ ULONG Len);
NTSTATUS PipaKbd_SendEnableSequence(_In_ PDEVICE_CONTEXT Ctx, _Out_ PULONG OkCount);
NTSTATUS PipaKbd_SpbReadOnce(_In_ PDEVICE_CONTEXT Ctx, _Out_ PULONG_PTR Got);
