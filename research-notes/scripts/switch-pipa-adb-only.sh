#!/system/bin/sh

LOG=/tmp/switch-pipa-adb-only.log
exec >"$LOG" 2>&1
set -x

G=/config/usb_gadget/g1
echo > "$G/UDC"
sleep 2
rm -f "$G/configs/b.1/mass_storage.0"
rm -f "$G/configs/b.1/mass_storage.1"
echo > "$G/functions/mass_storage.0/lun.0/file" 2>/dev/null
echo > "$G/functions/mass_storage.0/lun.1/file" 2>/dev/null
ln -s "$G/functions/mtp.gs0" "$G/configs/b.1/f1" 2>/dev/null
ln -s "$G/functions/ffs.adb" "$G/configs/b.1/f2" 2>/dev/null
echo a0743d79 > "$G/strings/0x409/serialnumber"
sleep 2
echo a600000.dwc3 > "$G/UDC"
echo DONE

