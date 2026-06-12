// device.c - resource parsing, power transitions, poll timer.
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

    // Open the SpbCx I2C target by resource-hub connection id.
    {
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
    }

    // Present the HID device.
    status = PipaKbd_VhfCreate(ctx);
    if (!NT_SUCCESS(status)) return status;

    // Replay the static enable/auth sequence captured from the Android HAL. Without it the
    // keyboard enumerates but never streams keys. Failure here is non-fatal (the chip may
    // already be enabled); log via the dump rather than failing D0.
    (VOID) PipaKbd_SendEnableSequence(ctx);

    // Start polling for key frames over I2C.
    WdfTimerStart(ctx->PollTimer, WDF_REL_TIMEOUT_IN_MS(NANO_POLL_MS));
    return STATUS_SUCCESS;
}

NTSTATUS
PipaKbdEvtD0Exit(_In_ WDFDEVICE Device, _In_ WDF_POWER_DEVICE_STATE TargetState)
{
    UNREFERENCED_PARAMETER(TargetState);
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    WdfTimerStop(ctx->PollTimer, TRUE);
    PipaKbd_VhfDestroy(ctx);
    if (ctx->SpbTarget) { WdfIoTargetClose(ctx->SpbTarget); ctx->SpbTarget = NULL; }
    return STATUS_SUCCESS;
}

// Passive-level: read one frame over I2C and dispatch its sub-packets to VHF.
VOID
PipaKbdEvtPollTimer(_In_ WDFTIMER Timer)
{
    PDEVICE_CONTEXT ctx = GetDeviceContext(WdfTimerGetParentObject(Timer));
    if (NT_SUCCESS(PipaKbd_SpbReadFrame(ctx))) {
        PipaKbd_ParseFrame(ctx, ctx->ReadBuffer, NANO_READ_LEN);
    }
}
