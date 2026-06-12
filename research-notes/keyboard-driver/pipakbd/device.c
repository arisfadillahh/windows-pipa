// device.c - resource parse + power transitions. On D0Entry: open I2C, send enable sequence.
#include "pipakbd.h"

NTSTATUS
PipaKbdEvtPrepareHardware(
    _In_ WDFDEVICE Device,
    _In_ WDFCMRESLIST ResourcesRaw,
    _In_ WDFCMRESLIST ResourcesTranslated)
{
    UNREFERENCED_PARAMETER(ResourcesRaw);
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    ULONG count = WdfCmResourceListGetCount(ResourcesTranslated);
    BOOLEAN haveI2c = FALSE;

    for (ULONG i = 0; i < count; i++) {
        PCM_PARTIAL_RESOURCE_DESCRIPTOR d = WdfCmResourceListGetDescriptor(ResourcesTranslated, i);
        if (d->Type == CmResourceTypeConnection &&
            d->u.Connection.Class == CM_RESOURCE_CONNECTION_CLASS_SERIAL &&
            d->u.Connection.Type  == CM_RESOURCE_CONNECTION_TYPE_SERIAL_I2C) {
            ctx->SpbConnectionId.LowPart  = d->u.Connection.IdLowPart;
            ctx->SpbConnectionId.HighPart = d->u.Connection.IdHighPart;
            haveI2c = TRUE;
        }
    }
    if (!haveI2c) return STATUS_DEVICE_CONFIGURATION_ERROR;
    return STATUS_SUCCESS;
}

NTSTATUS
PipaKbdEvtReleaseHardware(_In_ WDFDEVICE Device, _In_ WDFCMRESLIST ResourcesTranslated)
{
    UNREFERENCED_PARAMETER(ResourcesTranslated);
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    if (ctx->SpbTarget) { WdfIoTargetClose(ctx->SpbTarget); ctx->SpbTarget = NULL; }
    return STATUS_SUCCESS;
}

NTSTATUS
PipaKbdEvtD0Entry(_In_ WDFDEVICE Device, _In_ WDF_POWER_DEVICE_STATE PreviousState)
{
    UNREFERENCED_PARAMETER(PreviousState);
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    NTSTATUS status;

    WDF_IO_TARGET_OPEN_PARAMS open;
    WDFIOTARGET target;
    DECLARE_UNICODE_STRING_SIZE(path, RESOURCE_HUB_PATH_SIZE);

    status = WdfIoTargetCreate(Device, WDF_NO_OBJECT_ATTRIBUTES, &target);
    if (!NT_SUCCESS(status)) return status;
    RESOURCE_HUB_CREATE_PATH_FROM_ID(&path, ctx->SpbConnectionId.LowPart, ctx->SpbConnectionId.HighPart);
    WDF_IO_TARGET_OPEN_PARAMS_INIT_OPEN_BY_NAME(&open, &path, FILE_GENERIC_READ | FILE_GENERIC_WRITE);
    status = WdfIoTargetOpen(target, &open);
    if (!NT_SUCCESS(status)) { WdfObjectDelete(target); return status; }
    ctx->SpbTarget = target;
    return STATUS_SUCCESS;   // NO I2C I/O here - see SelfManagedIoInit (avoids 0x9F).
}

// Runs once at PASSIVE after the device and its SPB target are fully started. Safe place for
// the synchronous I2C work. Always returns success so a NAK never fails device start.
NTSTATUS
PipaKbdEvtSelfManagedIoInit(_In_ WDFDEVICE Device)
{
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);

    ULONG okCount = 0;
    NTSTATUS enStatus = PipaKbd_SendEnableSequence(ctx, &okCount);

    ULONG_PTR got = 0;
    NTSTATUS rdStatus = PipaKbd_SpbReadOnce(ctx, &got);
    ULONG rdHead = ((ULONG)ctx->ReadBuffer[0]) | ((ULONG)ctx->ReadBuffer[1] << 8) |
                   ((ULONG)ctx->ReadBuffer[2] << 16) | ((ULONG)ctx->ReadBuffer[3] << 24);
    ULONG gotL = (ULONG)got;

    RtlWriteRegistryValue(RTL_REGISTRY_SERVICES, L"pipakbd", L"EnableOk", REG_DWORD, &okCount, sizeof(ULONG));
    RtlWriteRegistryValue(RTL_REGISTRY_SERVICES, L"pipakbd", L"EnableStatus", REG_DWORD, &enStatus, sizeof(ULONG));
    RtlWriteRegistryValue(RTL_REGISTRY_SERVICES, L"pipakbd", L"ReadStatus", REG_DWORD, &rdStatus, sizeof(ULONG));
    RtlWriteRegistryValue(RTL_REGISTRY_SERVICES, L"pipakbd", L"ReadBytes", REG_DWORD, &gotL, sizeof(ULONG));
    RtlWriteRegistryValue(RTL_REGISTRY_SERVICES, L"pipakbd", L"ReadHead", REG_DWORD, &rdHead, sizeof(ULONG));
    return STATUS_SUCCESS;
}

NTSTATUS
PipaKbdEvtD0Exit(_In_ WDFDEVICE Device, _In_ WDF_POWER_DEVICE_STATE TargetState)
{
    UNREFERENCED_PARAMETER(TargetState);
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    if (ctx->SpbTarget) { WdfIoTargetClose(ctx->SpbTarget); ctx->SpbTarget = NULL; }
    return STATUS_SUCCESS;
}
