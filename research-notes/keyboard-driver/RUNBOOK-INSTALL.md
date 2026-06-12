# pipakbd — on-device install runbook

The driver is **built and test-signed in CI**. This is the turnkey procedure to get the
Xiaomi Pad 6 keyboard working under Windows.

## Artifacts

- **Driver package** (GitHub Release, latest `ci-*` tag of the repo):
  `pipakbd.sys`, `pipakbd.cat`, `pipakbd.inf`, `pipakbd-testcert.cer`
  (also kept locally at `pipakbd-build/`). The `.cer` is per-build — use the one from the
  same release as the `.sys`.
- **Boot image**: `D:\windows pipa\pipa_muold_touchmin_v31-kbd-nano-local.img`
  (v30 stable base — GIO0 clean + I2C2 IRQ 635, no SPI4 — plus the `KBD0` ACPI child so
  Windows enumerates `ACPI\NANO0803`).
- **Install helper**: `install-kbd.cmd` / `install-kbd.ps1`.

## Steps

1. **Stage files to the device** (Android temp-root + WINPIPA on F:):
   - copy the 4 package files **and** `install-kbd.cmd` + `install-kbd.ps1` to
     `F:\woa\pipakbd\`, then flush.
2. **Flash v31** to `boot_b`, set slot B, boot Windows.
   - `fastboot flash boot_b "D:\windows pipa\pipa_muold_touchmin_v31-kbd-nano-local.img"`
   - `fastboot set_active b` ; `fastboot reboot`
3. **In Windows**: Win+R -> `C:\woa\pipakbd\install-kbd.cmd` -> Enter -> **Yes** at UAC.
   It trusts the test cert, enables test-signing, installs the driver, binds it, and opens
   a log. Expect `ACPI\NANO0803\0` -> **Started**, service `pipakbd` RUNNING.
4. **Restart Windows once** (stays on slot B) so test-signing + the bind fully apply.
5. **Attach the keyboard cover and type.**

## If it doesn't type yet

- `ACPI\NANO0803\0` still Code 28 / no driver: cert not trusted or test-signing not active
  yet — re-run after the restart; confirm `bcdedit` shows `testsigning Yes`.
- Device Started but no keys: the chip likely needs its init handshake — `device.c`
  `EvtD0Entry` has a TODO to send the startup write(s) from `nano_driver.c`
  (`Nanosic_i2c_write`, host frames beginning `0x32 0x00 0x4F 0x31 ...`). Capture
  `C:\woa\install-kbd-log.txt` + the standard dump and iterate the frame engine.
- BSOD/bootloop (unlikely — DEMAND_START, PoFx-free): boot Android, remove the driver
  offline (`dism /Image:<F:> /Remove-Driver oemNN.inf`) and roll back boot_b to v30.

## Rollback ladder

v31 -> v30 -> v29 -> v27 -> v26 -> v25 -> v19 (all on `D:\windows pipa`). Android slot A
is never touched.

## Rebuilding the driver

Push any change under `research-notes/keyboard-driver/**`; GitHub Actions
(`build-pipakbd`) rebuilds `pipakbd.sys`, re-catalogs, test-signs, and publishes a new
`ci-<n>` Release. Always pair the `.sys`/`.cat` with the **same release's** `.cer`.
