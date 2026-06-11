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

    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attribs, DEVICE_CONTEXT);
    status = WdfDeviceCreate(&DeviceInit, &attribs, &device);
    if (!NT_SUCCESS(status)) return status;

    ctx = GetDeviceContext(device);
    RtlZeroMemory(ctx, sizeof(*ctx));
    ctx->Device = device;

    // Level-triggered GPIO attention interrupt -> ISR acknowledges, DPC does the I2C read
    // (I2C transfers are passive-level, so the work must happen in the DPC, not the ISR).
    {
        WDF_INTERRUPT_CONFIG ic;
        WDF_INTERRUPT_CONFIG_INIT(&ic, PipaKbdEvtInterruptIsr, PipaKbdEvtInterruptDpc);
        ic.PassiveHandling = TRUE;   // allow passive-level DPC for SPB I/O
        status = WdfInterruptCreate(device, &ic, WDF_NO_OBJECT_ATTRIBUTES, &ctx->Interrupt);
        if (!NT_SUCCESS(status)) return status;
    }

    return STATUS_SUCCESS;
}
