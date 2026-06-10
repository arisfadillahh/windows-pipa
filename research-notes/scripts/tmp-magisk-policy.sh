#!/system/bin/sh
magiskpolicy --live "permissive magisk"
magiskpolicy --live "allow magisk configfs dir *"
magiskpolicy --live "allow magisk configfs file *"
magiskpolicy --live "allow magisk configfs lnk_file *"
magiskpolicy --live "allow magisk sysfs dir *"
magiskpolicy --live "allow magisk sysfs file *"
ls -la /config/usb_gadget/g1/functions | head -30

