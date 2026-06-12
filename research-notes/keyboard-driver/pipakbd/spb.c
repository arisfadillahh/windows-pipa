// spb.c - I2C writes for slave 0x4C + the static keyboard enable sequence.
//
// Wire convention (kernel const_iaddr_bytes=1): every write is prefixed by 0x4C, then the
// 66-byte command payload. Captured byte-for-byte from the Android HAL (identical across
// reboots -> static, not a per-session challenge).
#include "pipakbd.h"

static const UCHAR g_EnableSeq[][15] = {
    {0x32,0x00,0x4E,0x31,0x80,0x38,0x25,0x01,0x01,0x5E,0x00,0x00,0x00,0x00,0x00}, // screen on
    {0x32,0x00,0x4E,0x31,0x80,0x38,0xA1,0x01,0x01,0xDA,0x00,0x00,0x00,0x00,0x00},
    {0x32,0x00,0x4E,0x30,0x80,0x18,0x01,0x01,0x00,0x18,0x00,0x00,0x00,0x00,0x00},
    {0x32,0x00,0x4E,0x31,0x80,0x38,0x2E,0x01,0xFC,0x62,0x00,0x00,0x00,0x00,0x00},
    {0x32,0x00,0x4E,0x31,0x80,0x38,0x23,0x01,0x64,0xBF,0x00,0x00,0x00,0x00,0x00},
    {0x32,0x00,0x4E,0x31,0x80,0x38,0x2E,0x01,0x00,0x66,0x00,0x00,0x00,0x00,0x00},
    {0x32,0x00,0x4E,0x30,0x80,0x18,0x01,0x01,0x00,0x18,0x00,0x00,0x00,0x00,0x00},
    {0x32,0x00,0x4F,0x31,0x80,0x38,0x36,0x36,0x02,0x01,0x4E,0x46,0x43,0x51,0x00}, // NFCQ
    {0x32,0x00,0x4F,0x31,0x80,0x38,0x36,0x26,0x02,0x02,0x45,0x44,0x65,0x06,0x4D},
    {0x32,0x00,0x4F,0x31,0x80,0x38,0x31,0x06,0x4D,0x49,0x41,0x55,0x54,0x48,0x37}, // MIAUTH7
    {0x32,0x00,0x4E,0x30,0x80,0x38,0x01,0x01,0x00,0x38,0x00,0x00,0x00,0x00,0x00},
    {0x32,0x00,0x4E,0x31,0x80,0x38,0x52,0x06,0x94,0x7B,0xAE,0x6B,0x65,0xD7,0xF3}, // key/enable
};

NTSTATUS
PipaKbd_SpbWriteFrame(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Frame, _In_ ULONG Len)
{
    WDF_MEMORY_DESCRIPTOR memDesc;
    UCHAR buf[1 + NANO_FRAME_BYTES];

    if (Ctx->SpbTarget == NULL) return STATUS_INVALID_DEVICE_STATE;
    if (Len > NANO_FRAME_BYTES) Len = NANO_FRAME_BYTES;

    RtlZeroMemory(buf, sizeof(buf));
    buf[0] = NANO_IADDR;
    RtlCopyMemory(&buf[1], Frame, Len);

    // Bounded timeout: if qci2c can't complete the transfer (SE clock not up on this minimal
    // platform), return STATUS_IO_TIMEOUT instead of wedging the power path -> hard reset.
    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&opts, WDF_REL_TIMEOUT_IN_MS(150));

    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&memDesc, buf, sizeof(buf));
    return WdfIoTargetSendWriteSynchronously(Ctx->SpbTarget, NULL, &memDesc, NULL, &opts, NULL);
}

NTSTATUS
PipaKbd_SendEnableSequence(_In_ PDEVICE_CONTEXT Ctx, _Out_ PULONG OkCount)
{
    NTSTATUS last = STATUS_SUCCESS;
    ULONG ok = 0;
    for (ULONG i = 0; i < RTL_NUMBER_OF(g_EnableSeq); i++) {
        NTSTATUS s = PipaKbd_SpbWriteFrame(Ctx, g_EnableSeq[i], 15);
        if (NT_SUCCESS(s)) ok++; else last = s;
        LARGE_INTEGER dt; dt.QuadPart = -(5 * 10 * 1000); // 5 ms between frames
        KeDelayExecutionThread(KernelMode, FALSE, &dt);
    }
    *OkCount = ok;
    return last;
}

// Diagnostic one-shot read: select 0x4C, read 68 bytes into Ctx->ReadBuffer.
NTSTATUS
PipaKbd_SpbReadOnce(_In_ PDEVICE_CONTEXT Ctx, _Out_ PULONG_PTR Got)
{
    NTSTATUS status;
    WDF_MEMORY_DESCRIPTOR wDesc, rDesc;
    UCHAR addr = NANO_IADDR;
    *Got = 0;
    if (Ctx->SpbTarget == NULL) return STATUS_INVALID_DEVICE_STATE;

    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&opts, WDF_REL_TIMEOUT_IN_MS(150));

    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&wDesc, &addr, sizeof(addr));
    status = WdfIoTargetSendWriteSynchronously(Ctx->SpbTarget, NULL, &wDesc, NULL, &opts, NULL);
    if (!NT_SUCCESS(status)) return status;

    RtlZeroMemory(Ctx->ReadBuffer, sizeof(Ctx->ReadBuffer));
    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&rDesc, Ctx->ReadBuffer, sizeof(Ctx->ReadBuffer));
    return WdfIoTargetSendReadSynchronously(Ctx->SpbTarget, NULL, &rDesc, NULL, &opts, Got);
}
