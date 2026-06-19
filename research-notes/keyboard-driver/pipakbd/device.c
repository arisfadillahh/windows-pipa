// device.c - resource parse, power transitions, enable sequence, and polling.
#include "pipakbd.h"

static VOID
PipaKbd_WriteDword(_In_ PCWSTR Name, _In_ ULONG Value)
{
    (VOID)RtlWriteRegistryValue(RTL_REGISTRY_SERVICES,
                                L"pipakbd",
                                Name,
                                REG_DWORD,
                                &Value,
                                sizeof(Value));
}

static VOID
PipaKbd_WritePollDiag(_In_ PDEVICE_CONTEXT Ctx)
{
    PipaKbd_WriteDword(L"PollCount", Ctx->PollCount);
    PipaKbd_WriteDword(L"PollOk", Ctx->PollOk);
    PipaKbd_WriteDword(L"PollTimeout", Ctx->PollTimeout);
    PipaKbd_WriteDword(L"PollError", Ctx->PollError);
    PipaKbd_WriteDword(L"LastReadStatus", (ULONG)Ctx->LastReadStatus);
    PipaKbd_WriteDword(L"LastReadHead", Ctx->LastReadHead);
}

static VOID
PipaKbd_DelayMs(_In_ ULONG Milliseconds)
{
    LARGE_INTEGER interval;
    interval.QuadPart = -((LONGLONG)Milliseconds * 10000);
    (VOID)KeDelayExecutionThread(KernelMode, FALSE, &interval);
}

#define PIPA_TLMM_GPIO_STRIDE          0x1000UL
#define PIPA_TLMM_GPIO_CFG_OFFSET      0x0000UL
#define PIPA_TLMM_GPIO_INOUT_OFFSET    0x0004UL
#define PIPA_TLMM_GPIO_FUNC_MASK       0x0000000FUL
#define PIPA_TLMM_GPIO_OUTPUT_ENABLE   (1UL << 9)
#define PIPA_TLMM_GPIO_OUT_HIGH        (1UL << 1)
#define PIPA_TLMM_BASE_PHYSICAL        0x0F100000ULL
#define PIPA_TLMM_LENGTH               0x00300000UL

static NTSTATUS
PipaKbd_TlmmWritePin(_In_ PDEVICE_CONTEXT Ctx, _In_ ULONG Pin, _In_ BOOLEAN High)
{
    ULONGLONG gpioOffset;
    volatile ULONG* cfgReg;
    volatile ULONG* inoutReg;
    ULONG cfg;
    ULONG inout;

    if (Ctx->TlmmBase == NULL) {
        return STATUS_DEVICE_NOT_CONNECTED;
    }

    gpioOffset = (ULONGLONG)Pin * PIPA_TLMM_GPIO_STRIDE;
    if (gpioOffset + PIPA_TLMM_GPIO_INOUT_OFFSET + sizeof(ULONG) > Ctx->TlmmLength) {
        return STATUS_INVALID_PARAMETER;
    }

    cfgReg = (volatile ULONG*)((PUCHAR)Ctx->TlmmBase + gpioOffset + PIPA_TLMM_GPIO_CFG_OFFSET);
    inoutReg = (volatile ULONG*)((PUCHAR)Ctx->TlmmBase + gpioOffset + PIPA_TLMM_GPIO_INOUT_OFFSET);

    inout = READ_REGISTER_ULONG(inoutReg);
    if (High) {
        inout |= PIPA_TLMM_GPIO_OUT_HIGH;
    } else {
        inout &= ~PIPA_TLMM_GPIO_OUT_HIGH;
    }
    WRITE_REGISTER_ULONG(inoutReg, inout);

    cfg = READ_REGISTER_ULONG(cfgReg);
    cfg &= ~PIPA_TLMM_GPIO_FUNC_MASK;       // function 0 = GPIO
    cfg |= PIPA_TLMM_GPIO_OUTPUT_ENABLE;
    WRITE_REGISTER_ULONG(cfgReg, cfg);

    KeMemoryBarrier();
    Ctx->TlmmLastPin = Pin;
    Ctx->TlmmLastCfg = READ_REGISTER_ULONG(cfgReg);
    Ctx->TlmmLastInOut = READ_REGISTER_ULONG(inoutReg);
    PipaKbd_WriteDword(L"TlmmLastPin", Ctx->TlmmLastPin);
    PipaKbd_WriteDword(L"TlmmLastCfg", Ctx->TlmmLastCfg);
    PipaKbd_WriteDword(L"TlmmLastInOut", Ctx->TlmmLastInOut);
    return STATUS_SUCCESS;
}

static NTSTATUS
PipaKbd_TlmmPowerOnKeyboard(_In_ PDEVICE_CONTEXT Ctx)
{
    NTSTATUS status;

    if (!Ctx->HaveTlmmMemory) {
        status = STATUS_NOT_FOUND;
        PipaKbd_WriteDword(L"TlmmPowerStatus", (ULONG)status);
        return status;
    }

    if (Ctx->TlmmBase == NULL) {
        status = STATUS_DEVICE_NOT_CONNECTED;
        PipaKbd_WriteDword(L"TlmmPowerStatus", (ULONG)status);
        return status;
    }

    // Pins from pipa.dts nanosic@4c: status=46, vdd=127, reset=141, sleep=155.
    status = PipaKbd_TlmmWritePin(Ctx, 141, FALSE);
    if (!NT_SUCCESS(status)) goto Exit;
    status = PipaKbd_TlmmWritePin(Ctx, 127, FALSE);
    if (!NT_SUCCESS(status)) goto Exit;
    status = PipaKbd_TlmmWritePin(Ctx, 46, FALSE);
    if (!NT_SUCCESS(status)) goto Exit;
    status = PipaKbd_TlmmWritePin(Ctx, 155, FALSE);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(5);

    status = PipaKbd_TlmmWritePin(Ctx, 127, TRUE);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(10);

    status = PipaKbd_TlmmWritePin(Ctx, 46, TRUE);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(5);

    status = PipaKbd_TlmmWritePin(Ctx, 155, TRUE);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(10);

    status = PipaKbd_TlmmWritePin(Ctx, 141, TRUE);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(30);

Exit:
    Ctx->TlmmPowerStatus = status;
    PipaKbd_WriteDword(L"TlmmPowerStatus", (ULONG)status);
    return status;
}

static NTSTATUS
PipaKbd_GpioWritePins(_In_ PDEVICE_CONTEXT Ctx, _In_ UCHAR Value)
{
    NTSTATUS status;
    WDF_MEMORY_DESCRIPTOR input;

    if (Ctx->GpioTarget == NULL) {
        status = STATUS_DEVICE_NOT_CONNECTED;
    } else {
        WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&input, &Value, sizeof(Value));
        status = WdfIoTargetSendIoctlSynchronously(Ctx->GpioTarget,
                                                   NULL,
                                                   IOCTL_GPIO_WRITE_PINS,
                                                   &input,
                                                   NULL,
                                                   NULL,
                                                   NULL);
    }

    Ctx->GpioLastValue = Value;
    PipaKbd_WriteDword(L"GpioLastValue", Ctx->GpioLastValue);
    PipaKbd_WriteDword(L"GpioLastStatus", (ULONG)status);
    return status;
}

static NTSTATUS
PipaKbd_PowerOnKeyboard(_In_ PDEVICE_CONTEXT Ctx)
{
    NTSTATUS status;

    if (!Ctx->HaveGpioIo) {
        status = STATUS_NOT_FOUND;
        PipaKbd_WriteDword(L"GpioPowerStatus", (ULONG)status);
        return status;
    }

    if (Ctx->GpioTarget == NULL) {
        status = STATUS_DEVICE_NOT_CONNECTED;
        PipaKbd_WriteDword(L"GpioPowerStatus", (ULONG)status);
        return status;
    }

    // GPIO resource bit order is reset, vdd, sleep.
    status = PipaKbd_GpioWritePins(Ctx, 0x00);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(5);

    status = PipaKbd_GpioWritePins(Ctx, 0x02);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(10);

    status = PipaKbd_GpioWritePins(Ctx, 0x06);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(10);

    status = PipaKbd_GpioWritePins(Ctx, 0x07);
    if (!NT_SUCCESS(status)) goto Exit;
    PipaKbd_DelayMs(30);

Exit:
    Ctx->GpioPowerStatus = status;
    PipaKbd_WriteDword(L"GpioPowerStatus", (ULONG)status);
    return status;
}

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
    ULONG i;

    ctx->HaveGpioIo = FALSE;
    ctx->GpioConnectionId.QuadPart = 0;
    ctx->GpioOpenStatus = STATUS_NOT_FOUND;
    ctx->GpioPowerStatus = STATUS_NOT_FOUND;
    ctx->GpioLastValue = 0;
    ctx->HaveTlmmMemory = FALSE;
    ctx->TlmmPhysical.QuadPart = 0;
    ctx->TlmmLength = 0;
    ctx->TlmmMapStatus = STATUS_NOT_FOUND;
    ctx->TlmmPowerStatus = STATUS_NOT_FOUND;
    ctx->TlmmLastPin = 0;
    ctx->TlmmLastCfg = 0;
    ctx->TlmmLastInOut = 0;
    PipaKbd_WriteDword(L"TlmmSource", 0);

    if (ctx->TlmmBase != NULL) {
        MmUnmapIoSpace(ctx->TlmmBase, ctx->TlmmLength);
        ctx->TlmmBase = NULL;
    }

    for (i = 0; i < count; i++) {
        PCM_PARTIAL_RESOURCE_DESCRIPTOR d = WdfCmResourceListGetDescriptor(ResourcesTranslated, i);
        if (d->Type == CmResourceTypeConnection &&
            d->u.Connection.Class == CM_RESOURCE_CONNECTION_CLASS_SERIAL &&
            d->u.Connection.Type  == CM_RESOURCE_CONNECTION_TYPE_SERIAL_I2C) {
            ctx->SpbConnectionId.LowPart  = d->u.Connection.IdLowPart;
            ctx->SpbConnectionId.HighPart = d->u.Connection.IdHighPart;
            haveI2c = TRUE;
        } else if (d->Type == CmResourceTypeConnection &&
                   d->u.Connection.Class == CM_RESOURCE_CONNECTION_CLASS_GPIO &&
                   d->u.Connection.Type  == CM_RESOURCE_CONNECTION_TYPE_GPIO_IO) {
            ctx->GpioConnectionId.LowPart  = d->u.Connection.IdLowPart;
            ctx->GpioConnectionId.HighPart = d->u.Connection.IdHighPart;
            ctx->HaveGpioIo = TRUE;
        } else if (d->Type == CmResourceTypeMemory) {
            ctx->TlmmPhysical = d->u.Memory.Start;
            ctx->TlmmLength = d->u.Memory.Length;
            ctx->HaveTlmmMemory = TRUE;
            PipaKbd_WriteDword(L"TlmmSource", 1);
        }
    }
    if (!ctx->HaveTlmmMemory) {
        ctx->TlmmPhysical.QuadPart = PIPA_TLMM_BASE_PHYSICAL;
        ctx->TlmmLength = PIPA_TLMM_LENGTH;
        ctx->HaveTlmmMemory = TRUE;
        PipaKbd_WriteDword(L"TlmmSource", 2);
    }
    PipaKbd_WriteDword(L"GpioSeen", ctx->HaveGpioIo ? 1 : 0);
    PipaKbd_WriteDword(L"TlmmSeen", ctx->HaveTlmmMemory ? 1 : 0);
    PipaKbd_WriteDword(L"TlmmBaseLow", ctx->TlmmPhysical.LowPart);
    PipaKbd_WriteDword(L"TlmmBaseHigh", ctx->TlmmPhysical.HighPart);
    PipaKbd_WriteDword(L"TlmmLength", ctx->TlmmLength);

    if (ctx->HaveTlmmMemory) {
        ctx->TlmmBase = MmMapIoSpace(ctx->TlmmPhysical, ctx->TlmmLength, MmNonCached);
        ctx->TlmmMapStatus = (ctx->TlmmBase != NULL) ? STATUS_SUCCESS : STATUS_INSUFFICIENT_RESOURCES;
    }
    PipaKbd_WriteDword(L"TlmmMapStatus", (ULONG)ctx->TlmmMapStatus);

    if (!haveI2c) return STATUS_DEVICE_CONFIGURATION_ERROR;
    return STATUS_SUCCESS;
}

NTSTATUS
PipaKbdEvtReleaseHardware(_In_ WDFDEVICE Device, _In_ WDFCMRESLIST ResourcesTranslated)
{
    UNREFERENCED_PARAMETER(ResourcesTranslated);
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    if (ctx->SpbTarget) { WdfIoTargetClose(ctx->SpbTarget); ctx->SpbTarget = NULL; }
    if (ctx->GpioTarget) { WdfIoTargetClose(ctx->GpioTarget); ctx->GpioTarget = NULL; }
    if (ctx->TlmmBase) { MmUnmapIoSpace(ctx->TlmmBase, ctx->TlmmLength); ctx->TlmmBase = NULL; }
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

    if (ctx->HaveGpioIo) {
        status = WdfIoTargetCreate(Device, WDF_NO_OBJECT_ATTRIBUTES, &target);
        if (NT_SUCCESS(status)) {
            RESOURCE_HUB_CREATE_PATH_FROM_ID(&path, ctx->GpioConnectionId.LowPart, ctx->GpioConnectionId.HighPart);
            WDF_IO_TARGET_OPEN_PARAMS_INIT_OPEN_BY_NAME(&open, &path, FILE_GENERIC_WRITE);
            status = WdfIoTargetOpen(target, &open);
            if (NT_SUCCESS(status)) {
                ctx->GpioTarget = target;
            } else {
                WdfObjectDelete(target);
            }
        }
    } else {
        status = STATUS_NOT_FOUND;
    }
    ctx->GpioOpenStatus = status;
    PipaKbd_WriteDword(L"GpioOpenStatus", (ULONG)status);

    return STATUS_SUCCESS;   // NO I2C I/O here - see SelfManagedIoInit (avoids 0x9F).
}

// Runs once at PASSIVE after the device and its SPB target are fully started. Safe place for
// the synchronous I2C work. Always returns success so a NAK never fails device start.
NTSTATUS
PipaKbdEvtSelfManagedIoInit(_In_ WDFDEVICE Device)
{
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    NTSTATUS vhfStatus;
    ULONG okCount = 0;
    NTSTATUS enStatus;

    vhfStatus = PipaKbd_VhfCreate(ctx);
    PipaKbd_WriteDword(L"VhfStatus", (ULONG)vhfStatus);

    (VOID)PipaKbd_TlmmPowerOnKeyboard(ctx);
    (VOID)PipaKbd_PowerOnKeyboard(ctx);

    enStatus = PipaKbd_SendEnableSequence(ctx, &okCount);
    PipaKbd_WriteDword(L"EnableOk", okCount);
    PipaKbd_WriteDword(L"EnableStatus", (ULONG)enStatus);

    if (NT_SUCCESS(vhfStatus) && ctx->PollTimer != NULL) {
        ctx->StopPolling = FALSE;
        WdfTimerStart(ctx->PollTimer, WDF_REL_TIMEOUT_IN_MS(20));
    }
    return STATUS_SUCCESS;
}

NTSTATUS
PipaKbdEvtD0Exit(_In_ WDFDEVICE Device, _In_ WDF_POWER_DEVICE_STATE TargetState)
{
    UNREFERENCED_PARAMETER(TargetState);
    PDEVICE_CONTEXT ctx = GetDeviceContext(Device);
    ctx->StopPolling = TRUE;
    if (ctx->PollTimer != NULL) {
        WdfTimerStop(ctx->PollTimer, TRUE);
    }
    PipaKbd_VhfDestroy(ctx);
    if (ctx->SpbTarget) { WdfIoTargetClose(ctx->SpbTarget); ctx->SpbTarget = NULL; }
    if (ctx->GpioTarget) { WdfIoTargetClose(ctx->GpioTarget); ctx->GpioTarget = NULL; }
    return STATUS_SUCCESS;
}

VOID
PipaKbdEvtPollTimer(_In_ WDFTIMER Timer)
{
    WDFDEVICE device = GetTimerContext(Timer)->Device;
    PDEVICE_CONTEXT ctx = GetDeviceContext(device);
    ULONG_PTR got = 0;
    NTSTATUS status;

    if (ctx->StopPolling || ctx->SpbTarget == NULL) {
        return;
    }

    status = PipaKbd_SpbReadOnce(ctx, &got);
    ctx->PollCount++;
    ctx->LastReadStatus = status;
    ctx->LastReadHead = ((ULONG)ctx->ReadBuffer[0]) |
                        ((ULONG)ctx->ReadBuffer[1] << 8) |
                        ((ULONG)ctx->ReadBuffer[2] << 16) |
                        ((ULONG)ctx->ReadBuffer[3] << 24);

    if (NT_SUCCESS(status) && got > 0) {
        ctx->PollOk++;
        PipaKbd_ParseFrame(ctx, ctx->ReadBuffer, (ULONG)got);
        PipaKbd_WriteDword(L"ReadBytes", (ULONG)got);
        PipaKbd_WriteDword(L"ReadHead", ctx->LastReadHead);
        PipaKbd_WritePollDiag(ctx);
        WdfTimerStart(ctx->PollTimer, WDF_REL_TIMEOUT_IN_MS(1));
        return;
    }

    if (status == STATUS_IO_TIMEOUT) {
        ctx->PollTimeout++;
    } else {
        ctx->PollError++;
    }

    if ((ctx->PollCount % 32) == 0 || status != STATUS_IO_TIMEOUT) {
        PipaKbd_WritePollDiag(ctx);
    }

    WdfTimerStart(ctx->PollTimer, WDF_REL_TIMEOUT_IN_MS(30));
}
