#!/system/bin/sh
set -eu

G=/config/usb_gadget/g1
CFG="$G/configs/b.1"
FUNC="$G/functions/mass_storage.0"
LUN="$FUNC/lun.0"

echo "EXPOSE_WINPIPA_START"
id
echo "context=$(cat /proc/self/attr/current)"
echo "udc_before=$(cat "$G/UDC" 2>/dev/null || true)"

mkdir -p "$CFG"

if [ ! -e "$CFG/mass_storage.0" ]; then
  ln -s "$FUNC" "$CFG/mass_storage.0"
fi

echo 0xEF > "$G/bDeviceClass"
echo 0x02 > "$G/bDeviceSubClass"
echo 0x01 > "$G/bDeviceProtocol"

echo "" > "$G/UDC" 2>/dev/null || true
echo 0 > "$LUN/ro" 2>/dev/null || true
echo 0 > "$LUN/removable" 2>/dev/null || true
echo /dev/block/sda36 > "$LUN/file"
echo a600000.dwc3 > "$G/UDC"

echo "lun_file=$(cat "$LUN/file")"
echo "ro=$(cat "$LUN/ro" 2>/dev/null || true)"
echo "udc_after=$(cat "$G/UDC" 2>/dev/null || true)"
echo "EXPOSE_WINPIPA_DONE"

