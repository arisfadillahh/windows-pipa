#!/system/bin/sh
LOG=/tmp/massonly.log
exec >"$LOG" 2>&1
set -x

G=/config/usb_gadget/g1
setenforce 0 2>/dev/null
sync

mkdir -p "$G/functions/mass_storage.0"

echo /dev/block/sda > "$G/functions/mass_storage.0/lun.0/file"
echo 0 > "$G/functions/mass_storage.0/lun.0/removable"
echo 0 > "$G/functions/mass_storage.0/lun.0/ro"

echo "" > "$G/UDC"
sleep 2

rm -f "$G/configs/b.1/f1"
rm -f "$G/configs/b.1/f2"
rm -f "$G/configs/b.1/mass_storage.0"
ln -s "$G/functions/mass_storage.0" "$G/configs/b.1/mass_storage.0"

echo 0x00 > "$G/bDeviceClass"
echo 0x00 > "$G/bDeviceSubClass"
echo 0x00 > "$G/bDeviceProtocol"

sleep 2
echo a600000.dwc3 > "$G/UDC"
sleep 1

cat "$G/UDC"
cat "$G/functions/mass_storage.0/lun.0/file"
ls -la "$G/configs/b.1"

