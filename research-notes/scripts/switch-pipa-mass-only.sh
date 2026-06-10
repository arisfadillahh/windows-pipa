#!/system/bin/sh

LOG=/tmp/switch-pipa-mass-only.log
exec >"$LOG" 2>&1
set -x

G=/config/usb_gadget/g1
echo > "$G/UDC"
sleep 2
rm -f "$G/configs/b.1/f1"
rm -f "$G/configs/b.1/f2"
sleep 2
echo a600000.dwc3 > "$G/UDC"
echo DONE

