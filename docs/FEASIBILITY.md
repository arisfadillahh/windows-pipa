# Feasibility notes

Device: Xiaomi Pad 6 (`pipa`), Snapdragon 870 / Qualcomm SM8250.

## Current evidence

The target device already runs postmarketOS with GPU and touchscreen working.
That strongly helps Linux-side hardware mapping:

- Device tree and power resources are known well enough for Linux.
- Adreno works through Linux DRM/MSM + Mesa/Freedreno.
- Touch controller wiring is known well enough for Linux input.

## Windows-specific blockers

Windows cannot directly use Linux kernel drivers. Windows needs:

- UEFI firmware and ACPI tables.
- ARM64 Windows kernel drivers.
- WDDM display driver for GPU acceleration.
- Windows camera stack drivers for ISP, CSI, sensors, and tuning data.

## Component matrix

| Component | Probability | Notes |
| --- | --- | --- |
| Boot to UEFI/Windows PE | High | Needs pipa UEFI and correct ESP. |
| Display basic | High | Framebuffer/GOP path should be enough for first boot. |
| Storage/USB | Medium-high | Depends on ACPI and existing Windows class drivers. |
| RAM full size | Medium | UEFI memory map must expose all usable RAM. |
| Touchscreen | Medium | More realistic if controller can be represented as HID-over-I2C. |
| Wi-Fi/Bluetooth | Medium | Depends on chip and reusable ARM64 Windows drivers. |
| Audio | Low-medium | Qualcomm ADSP routing is usually vendor-specific. |
| GPU acceleration | Low-medium | Needs compatible Adreno WDDM ARM64 driver. |
| Camera | Low | ISP, sensors, tuning, and power sequencing are hard. |
| Full daily driver | Low-medium | Depends on GPU/audio/camera/sleep. |

## Research lanes

1. Build a reliable pipa UEFI/ACPI base.
2. Reuse or adapt SM8250 Windows drivers when legally available.
3. Map Linux DTS nodes to Windows ACPI devices.
4. Start with touch and battery because they are simpler than GPU/camera.
5. Treat GPU and camera as separate reverse-engineering projects.

