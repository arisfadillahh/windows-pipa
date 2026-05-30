# Driver roadmap

This directory is intentionally empty except for templates and notes. Do not
commit proprietary Xiaomi, Qualcomm, or Microsoft driver binaries unless their
license explicitly allows redistribution.

## Priority order

1. ACPI tables for pipa board resources.
2. Storage, USB, and display boot path.
3. Touchscreen as HID-over-I2C or a small KMDF driver.
4. Battery, charger, buttons, sensors.
5. Wi-Fi/Bluetooth driver matching the actual module.
6. Audio DSP and codec routing.
7. Adreno WDDM GPU acceleration.
8. Camera ISP, CSI, sensor, and tuning stack.

## Driver injection

Put redistributable Windows ARM64 `.inf` driver folders under `drivers\vendor`.
Then pass:

```powershell
.\scripts\Install-PipaWindows.ps1 -DriverPath ".\drivers\vendor" ...
```

The installer uses offline DISM driver injection.

