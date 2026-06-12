// driver.c - DriverEntry / device-add for pipakbd.
#include "pipakbd.h"

DRIVER_INITIALIZE DriverEntry;

NTSTATUS
DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    WDF_DRIVER_CONFIG config;
    WDF_DRIVER_CONFIG_INIT(&config, PipaKbdEvtDeviceAdd);
    return WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES, &config, WDF_NO_HANDLE);
}

NTSTATUS
PipaKbdEvtDeviceAdd(_In_ WDFDRIVER Driver, _Inout_ PWDFDEVICE_INIT DeviceInit)
{
    UNREFERENCED_PARAMETER(Driver);
    NTSTATUS status;
    WDF_PNPPOWER_EVENT_CALLBACKS pnp;
    WDF_OBJECT_ATTRIBUTES attribs;
    WDFDEVICE device;
    PDEVICE_CONTEXT ctx;

    WDF_PNPPOWER_EVENT_CALLBACKS_INIT(&pnp);
    pnp.EvtDevicePrepareHardware = PipaKbdEvtPrepareHardware;
    pnp.EvtDeviceReleaseHardware = PipaKbdEvtReleaseHardware;
    pnp.EvtDeviceD0Entry         = PipaKbdEvtD0Entry;
    pnp.EvtDeviceD0Exit          = PipaKbdEvtD0Exit;
    WdfDeviceInitSetPnpPowerEventCallbacks(DeviceInit, &pnp);

    // Passive-level callbacks so the poll timer can issue synchronous SPB (I2C) I/O.
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attribs, DEVICE_CONTEXT);
    attribs.ExecutionLevel = WdfExecutionLevelPassive;

    status = WdfDeviceCreate(&DeviceInit, &attribs, &device);
    if (!NT_SUCCESS(status)) return status;

    ctx = GetDeviceContext(device);
    RtlZeroMemory(ctx, sizeof(*ctx));
    ctx->Device = device;

    // Periodic passive-level timer for I2C key-frame polling (no GpioInt: GIO0 interrupt
    // delivery is unreliable and caused STATUS_DEVICE_POWER_FAILURE at start).
    {
        WDF_TIMER_CONFIG tc;
        WDF_OBJECT_ATTRIBUTES ta;
        WDF_TIMER_CONFIG_INIT_PERIODIC(&tc, PipaKbdEvtPollTimer, NANO_POLL_MS);
        WDF_OBJECT_ATTRIBUTES_INIT(&ta);
        ta.ParentObject = device;
        ta.ExecutionLevel = WdfExecutionLevelPassive;
        status = WdfTimerCreate(&tc, &ta, &ctx->PollTimer);
        if (!NT_SUCCESS(status)) return status;
    }

    return STATUS_SUCCESS;
}
