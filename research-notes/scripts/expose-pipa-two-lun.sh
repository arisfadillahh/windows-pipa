#!/system/bin/sh

LOG=/tmp/expose-pipa-two-lun.log
exec >"$LOG" 2>&1
set -x

sync
umount /mnt/winpipa 2>/dev/null
umount /mnt/esp 2>/dev/null

G=/config/usb_gadget/g1
echo > "$G/UDC"
sleep 3

rm -f "$G/configs/b.1/f1"
rm -f "$G/configs/b.1/f2"
rm -f "$G/configs/b.1/mass_storage.0"
rm -f "$G/configs/b.1/mass_storage.1"

echo > "$G/functions/mass_storage.1/lun.0/file" 2>/dev/null
rmdir "$G/functions/mass_storage.1" 2>/dev/null

mkdir -p "$G/functions/mass_storage.0/lun.1"
echo /dev/block/sda36 > "$G/functions/mass_storage.0/lun.0/file"
echo 1 > "$G/functions/mass_storage.0/lun.0/removable"
echo 0 > "$G/functions/mass_storage.0/lun.0/ro"
echo /dev/block/sda35 > "$G/functions/mass_storage.0/lun.1/file"
echo 1 > "$G/functions/mass_storage.0/lun.1/removable"
echo 0 > "$G/functions/mass_storage.0/lun.1/ro"

ln -s "$G/functions/mass_storage.0" "$G/configs/b.1/mass_storage.0"
echo PIPAREPAIR3 > "$G/strings/0x409/serialnumber"
echo 0x00 > "$G/bDeviceClass"
echo 0x00 > "$G/bDeviceSubClass"
echo 0x00 > "$G/bDeviceProtocol"
sleep 2
echo a600000.dwc3 > "$G/UDC"
echo DONE

