#!/system/bin/sh

LOG=/tmp/reenumerate-pipa-mass-removable.log
exec >"$LOG" 2>&1
set -x

G=/config/usb_gadget/g1
echo > "$G/UDC"
sleep 3
echo 1 > "$G/functions/mass_storage.0/lun.0/removable"
echo 1 > "$G/functions/mass_storage.1/lun.0/removable"
echo PIPAREPAIR2 > "$G/strings/0x409/serialnumber"
sleep 2
echo a600000.dwc3 > "$G/UDC"
echo DONE

