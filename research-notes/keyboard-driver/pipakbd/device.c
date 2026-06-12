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

    // The whole point: unlock the keyboard. Non-fatal if a frame NAKs (chip may already be up).
    (VOID) PipaKbd_SendEnableSequence(ctx);
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
