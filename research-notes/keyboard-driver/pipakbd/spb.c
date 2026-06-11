// spb.c - SpbCx (I2C) read/write helpers against the slave-0x4C target.
#include "pipakbd.h"

NTSTATUS
PipaKbd_SpbReadFrame(_In_ PDEVICE_CONTEXT Ctx)
{
    NTSTATUS status;
    WDF_MEMORY_DESCRIPTOR memDesc;
    ULONG_PTR bytesRead = 0;

    if (Ctx->SpbTarget == NULL) return STATUS_INVALID_DEVICE_STATE;

    RtlZeroMemory(Ctx->ReadBuffer, sizeof(Ctx->ReadBuffer));
    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&memDesc, Ctx->ReadBuffer, sizeof(Ctx->ReadBuffer));

    // Plain I2C read of NANO_READ_LEN (68) bytes; the bus address comes from the
    // connection-id target so no addressing prefix is needed here.
    status = WdfIoTargetSendReadSynchronously(
                Ctx->SpbTarget, NULL, &memDesc, NULL, NULL, &bytesRead);

    if (NT_SUCCESS(status) && bytesRead < 3) status = STATUS_DEVICE_DATA_ERROR;
    return status;
}

NTSTATUS
PipaKbd_SpbWrite(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Data, _In_ ULONG Len)
{
    WDF_MEMORY_DESCRIPTOR memDesc;
    if (Ctx->SpbTarget == NULL) return STATUS_INVALID_DEVICE_STATE;
    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&memDesc, (PVOID)Data, Len);
    return WdfIoTargetSendWriteSynchronously(Ctx->SpbTarget, NULL, &memDesc, NULL, NULL, NULL);
}
