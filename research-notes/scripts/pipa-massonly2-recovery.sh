#!/system/bin/sh
LOG=/tmp/massonly2.log
exec >"$LOG" 2>&1
set -x

setenforce 0 2>/dev/null
G=/config/usb_gadget/g1

mkdir -p "$G/functions/mass_storage.0"

echo "" > "$G/UDC"
sleep 3

rm -f "$G/configs/b.1/f1"
rm -f "$G/configs/b.1/f2"
rm -f "$G/configs/b.1/ffs.adb"
rm -f "$G/configs/b.1/mass_storage.0"

echo /dev/block/sda > "$G/functions/mass_storage.0/lun.0/file"
echo 0 > "$G/functions/mass_storage.0/lun.0/removable"
echo 0 > "$G/functions/mass_storage.0/lun.0/ro"
echo 0 > "$G/functions/mass_storage.0/lun.0/cdrom"

ln -s "$G/functions/mass_storage.0" "$G/configs/b.1/mass_storage.0"

echo 0x18d1 > "$G/idVendor"
echo 0x4ee1 > "$G/idProduct"
echo PIPAMASS > "$G/strings/0x409/serialnumber"
echo 0x00 > "$G/bDeviceClass"
echo 0x00 > "$G/bDeviceSubClass"
echo 0x00 > "$G/bDeviceProtocol"

sleep 2
echo a600000.dwc3 > "$G/UDC"
sleep 2

echo "UDC=$(cat "$G/UDC")"
ls -la "$G/configs/b.1"
cat "$G/functions/mass_storage.0/lun.0/file"
cat /sys/class/udc/*/state 2>/dev/null

