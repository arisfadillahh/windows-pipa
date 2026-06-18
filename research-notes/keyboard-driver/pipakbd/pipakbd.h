// pipakbd.h - Nanosic 803 keyboard/touchpad driver.
//
// The pipa keyboard cover is not HID-over-I2C. Android reads 68-byte Nanosic frames from
// I2C slave 0x4C and forwards the HID-formatted slices into virtual HID devices. This
// driver mirrors that: replay the fixed enable sequence, poll frames, then submit reports
// through VHF.
#pragma once

#include <ntddk.h>
#include <wdf.h>
#include <hidport.h>
#include <vhf.h>
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

// The ACPI I2cSerialBus resource already selects slave 0x4C. The Nanosic command bytes
// seen in Android dmesg start directly with 0x32; do not prefix 0x4C as payload data.
#define NANO_FRAME_BYTES        66          // maximum command payload

#define NANO_READ_LEN   68
#define NANO_FRAME_MAGIC 0x57

#define NANO_T_MOUSE          0x02
#define NANO_T_KEYBOARD       0x05
#define NANO_T_CONSUMER       0x06
#define NANO_T_TOUCH          0x19
#define NANO_T_VENDOR16       0x22
#define NANO_T_VENDOR32       0x23
#define NANO_T_VENDOR_REST_A  0x24
#define NANO_T_VENDOR_REST_B  0x26

#define NANO_L_MOUSE          8
#define NANO_L_KEYBOARD       9
#define NANO_L_CONSUMER       5
#define NANO_L_TOUCH          21

#define NANO_GROUP_IS_VALID(g) ((g) == 0x39 || (g) == 0x4A || (g) == 0x5B || (g) == 0x6C)

typedef struct _DEVICE_CONTEXT {
    WDFDEVICE       Device;
    WDFIOTARGET     SpbTarget;
    WDFTIMER        PollTimer;
    VHFHANDLE       VhfHandle;
    LARGE_INTEGER   SpbConnectionId;
    UCHAR           ReadBuffer[NANO_READ_LEN];
    BOOLEAN         VhfStarted;
    BOOLEAN         StopPolling;
    ULONG           PollCount;
    ULONG           PollOk;
    ULONG           PollTimeout;
    ULONG           PollError;
    NTSTATUS        LastReadStatus;
    ULONG           LastReadHead;
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

typedef struct _TIMER_CONTEXT {
    WDFDEVICE Device;
} TIMER_CONTEXT, *PTIMER_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(TIMER_CONTEXT, GetTimerContext)

EVT_WDF_DRIVER_DEVICE_ADD        PipaKbdEvtDeviceAdd;
EVT_WDF_DEVICE_PREPARE_HARDWARE  PipaKbdEvtPrepareHardware;
EVT_WDF_DEVICE_RELEASE_HARDWARE  PipaKbdEvtReleaseHardware;
EVT_WDF_DEVICE_D0_ENTRY          PipaKbdEvtD0Entry;
EVT_WDF_DEVICE_D0_EXIT           PipaKbdEvtD0Exit;
EVT_WDF_DEVICE_SELF_MANAGED_IO_INIT PipaKbdEvtSelfManagedIoInit;
EVT_WDF_TIMER                    PipaKbdEvtPollTimer;

NTSTATUS PipaKbd_SpbWriteFrame(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Frame, _In_ ULONG Len);
NTSTATUS PipaKbd_SendEnableSequence(_In_ PDEVICE_CONTEXT Ctx, _Out_ PULONG OkCount);
NTSTATUS PipaKbd_SpbReadOnce(_In_ PDEVICE_CONTEXT Ctx, _Out_ PULONG_PTR Got);
VOID PipaKbd_ParseFrame(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Buf, _In_ ULONG Len);
NTSTATUS PipaKbd_VhfCreate(_In_ PDEVICE_CONTEXT Ctx);
VOID PipaKbd_VhfDestroy(_In_ PDEVICE_CONTEXT Ctx);
VOID PipaKbd_VhfSubmitReport(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Report, _In_ ULONG Len);
