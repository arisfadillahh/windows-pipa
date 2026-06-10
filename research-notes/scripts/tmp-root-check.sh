#!/system/bin/sh
echo ROOTCHECK
id
cat /proc/self/attr/current
getenforce
ls -ld /config /config/usb_gadget /config/usb_gadget/g1 /config/usb_gadget/g1/functions 2>&1
ls -la /config/usb_gadget/g1/functions 2>&1 | head -40

