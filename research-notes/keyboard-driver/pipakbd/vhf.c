// vhf.c - Microsoft Virtual HID Framework glue. Presents the 4 captured collections and
// passes chip reports straight through (the slice already includes the Report ID).
#include "pipakbd.h"
#include "report_descriptor.h"

NTSTATUS
PipaKbd_VhfCreate(_In_ PDEVICE_CONTEXT Ctx)
{
    NTSTATUS status;
    VHF_CONFIG cfg;

    if (Ctx->VhfHandle != NULL) return STATUS_SUCCESS;

    VHF_CONFIG_INIT(&cfg,
                    WdfDeviceWdmGetDeviceObject(Ctx->Device),
                    (USHORT)sizeof(g_PipaKbdReportDescriptor),
                    (PUCHAR)g_PipaKbdReportDescriptor);

    // Identify as the Xiaomi keyboard so existing per-VID quirks/PnP behave consistently.
    cfg.VendorID  = 0x15D9;
    cfg.ProductID = 0x00A3;
    cfg.VersionNumber = 0x0001;

    status = VhfCreate(&cfg, &Ctx->VhfHandle);
    if (!NT_SUCCESS(status)) { Ctx->VhfHandle = NULL; return status; }

    status = VhfStart(Ctx->VhfHandle);
    if (!NT_SUCCESS(status)) {
        VhfDelete(Ctx->VhfHandle, TRUE);
        Ctx->VhfHandle = NULL;
        return status;
    }
    Ctx->VhfStarted = TRUE;
    return STATUS_SUCCESS;
}

VOID
PipaKbd_VhfDestroy(_In_ PDEVICE_CONTEXT Ctx)
{
    if (Ctx->VhfHandle != NULL) {
        VhfDelete(Ctx->VhfHandle, TRUE);
        Ctx->VhfHandle = NULL;
        Ctx->VhfStarted = FALSE;
    }
}

VOID
PipaKbd_VhfSubmitReport(_In_ PDEVICE_CONTEXT Ctx, _In_reads_(Len) const UCHAR* Report, _In_ ULONG Len)
{
    HID_XFER_PACKET pkt;
    if (!Ctx->VhfStarted || Len == 0) return;

    RtlZeroMemory(&pkt, sizeof(pkt));
    pkt.reportId       = Report[0];          // chip slice already leads with the Report ID
    pkt.reportBuffer   = (PUCHAR)Report;
    pkt.reportBufferLen = Len;

    (VOID)VhfReadReportSubmit(Ctx->VhfHandle, &pkt);
}
