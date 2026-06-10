#!/system/bin/sh
set -u

G=/config/usb_gadget/g1
C=$G/configs/b.1
F=$G/functions/mass_storage.0
LOG=/tmp/pipa-massonly-timer.log
SECONDS_TO_WAIT="${1:-300}"

exec >>"$LOG" 2>&1
echo "=== pipa mass-only timer start ==="
date

cat /dev/null > "$G/UDC" || true

rm -f "$C/f1" "$C/ffs.adb" "$C/mass_storage.0" 2>/dev/null || true
mkdir -p "$F"

echo 0 > "$F/stall" || true
echo /dev/block/sda36 > "$F/lun.0/file"
echo 0 > "$F/lun.0/removable"
echo 0 > "$F/lun.0/cdrom"
echo 0 > "$F/lun.0/ro"

ln -s "$F" "$C/mass_storage.0"

echo 0x18d1 > "$G/idVendor"
echo 0x4ee0 > "$G/idProduct"
echo 0x08 > "$G/bDeviceClass"
echo 0x06 > "$G/bDeviceSubClass"
echo 0x50 > "$G/bDeviceProtocol"

echo a600000.dwc3 > "$G/UDC"
echo "mass-storage-only exported /dev/block/sda36 for ${SECONDS_TO_WAIT}s"

sleep "$SECONDS_TO_WAIT"
sync
echo "timer elapsed, rebooting bootloader"
reboot bootloader

