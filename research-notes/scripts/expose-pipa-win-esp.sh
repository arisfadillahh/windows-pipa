#!/system/bin/sh

LOG=/tmp/expose-pipa-win-esp.log
exec >"$LOG" 2>&1
set -x

sync
umount /mnt/winpipa 2>/dev/null
umount /mnt/esp 2>/dev/null

G=/config/usb_gadget/g1
mkdir -p "$G/functions/mass_storage.0"
mkdir -p "$G/functions/mass_storage.1"

echo /dev/block/sda36 > "$G/functions/mass_storage.0/lun.0/file"
echo 0 > "$G/functions/mass_storage.0/lun.0/removable"
echo 0 > "$G/functions/mass_storage.0/lun.0/ro"

echo /dev/block/sda35 > "$G/functions/mass_storage.1/lun.0/file"
echo 0 > "$G/functions/mass_storage.1/lun.0/removable"
echo 0 > "$G/functions/mass_storage.1/lun.0/ro"

echo > "$G/UDC"
sleep 2

rm -f "$G/configs/b.1/mass_storage.0"
rm -f "$G/configs/b.1/mass_storage.1"
ln -s "$G/functions/mass_storage.0" "$G/configs/b.1/mass_storage.0"
ln -s "$G/functions/mass_storage.1" "$G/configs/b.1/mass_storage.1"

echo 0x00 > "$G/bDeviceClass"
echo 0x00 > "$G/bDeviceSubClass"
echo 0x00 > "$G/bDeviceProtocol"
echo a600000.dwc3 > "$G/UDC"

cat "$G/functions/mass_storage.0/lun.0/file"
cat "$G/functions/mass_storage.1/lun.0/file"
echo DONE

