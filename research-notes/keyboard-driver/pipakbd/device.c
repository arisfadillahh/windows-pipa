// device.c - resource parsing, power transitions, interrupt handling.
#include "pipakbd.h"

// Pull the I2cSerialBus connection id and the GpioInt out of the translated resource list.
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
        // The GpioInt is surfaced as CmResourceTypeInterrupt and is bound automatically
        // to ctx->Interrupt by the framework (WdfInterruptCreate in EvtDeviceAdd).
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

    // Open the SpbCx I2C target.
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

    // Bring the chip up: VHF first so reports can flow immediately.
    status = PipaKbd_VhfCreate(ctx);
    if (!NT_SUCCESS(status)) return status;

    // TODO(device-init): replay the firmware handshake the kernel probe issues before the
    // chip streams. Observed host->chip write begins 0x32 0x00 0x4F 0x31 ...
    // (FIELD_HOST). Capture the exact init write(s) from nano_driver.c / nano_i2c.c
    // (Nanosic_i2c_write, 66-byte writes) and send via PipaKbd_SpbWrite() here.

    return STATUS_SUCCESS;
}

NTSTATUS
PipaKbdEvtD0Exit(_In_ WDFDEVICE Device, _In_ WDF_POWER_DEVICE_STATE TargetState)
{
    UNREFERENCED_PARAMETER(TargetState);
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    PipaKbd_VhfDestroy(ctx);
    if (ctx->SpbTarget) { WdfIoTargetClose(ctx->SpbTarget); ctx->SpbTarget = NULL; }
    return STATUS_SUCCESS;
}

BOOLEAN
PipaKbdEvtInterruptIsr(_In_ WDFINTERRUPT Interrupt, _In_ ULONG MessageId)
{
    UNREFERENCED_PARAMETER(MessageId);
    // GpioInt is ours; defer all I2C work to the (passive-level) DPC.
    WdfInterruptQueueDpcForIsr(Interrupt);
    return TRUE;
}

VOID
PipaKbdEvtInterruptDpc(_In_ WDFINTERRUPT Interrupt, _In_ WDFOBJECT AssociatedObject)
{
    UNREFERENCED_PARAMETER(AssociatedObject);
    PDEVICE_CONTEXT ctx = GetDeviceContext(WdfInterruptGetDevice(Interrupt));

    // Drain the chip: one read per attention assertion (one frame can hold several
    // sub-packets; PipaKbd_ParseFrame walks them all).
    if (NT_SUCCESS(PipaKbd_SpbReadFrame(ctx))) {
        PipaKbd_ParseFrame(ctx, ctx->ReadBuffer, NANO_READ_LEN);
    }
}
