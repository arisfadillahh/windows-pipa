#!/system/bin/sh
OUT=/data/local/tmp/pipa-keyboard-rootdump-root
rm -rf "$OUT"
mkdir -p "$OUT/hid" "$OUT/bin"

{
  echo "date=$(date)"
  id
  getenforce
  setenforce 0 2>/dev/null || true
  echo "after_setenforce=$(getenforce 2>/dev/null)"
  getprop ro.boot.slot_suffix
  getprop ro.boot.verifiedbootstate
} > "$OUT/root-state.txt" 2>&1

{
  echo "=== /dev/nanodev0 ==="
  ls -la /dev/nanodev0 2>&1
  echo "=== /sys/class/nanodev ==="
  ls -la /sys/class/nanodev /sys/class/nanodev/nanodev0 2>&1
  echo "=== readlink ==="
  readlink -f /sys/class/nanodev/nanodev0 2>&1
  echo "=== files ==="
  for f in /sys/class/nanodev/nanodev0/*; do
    echo "--- $f ---"
    cat "$f" 2>&1 | head -120
  done
} > "$OUT/nanodev.txt" 2>&1

{
  echo "=== onewire platform paths ==="
  find /sys/devices/platform/soc -maxdepth 4 \( -iname '*onewire*' -o -iname '*nano*' -o -iname '*keyboard*' \) 2>&1
  for n in /sys/devices/platform/soc/soc:onewire_gpio /sys/devices/platform/soc/soc:onewire_slave_gpio; do
    echo "=== $n ==="
    ls -la "$n" 2>&1
    echo "driver=$(readlink -f "$n/driver" 2>/dev/null)"
    echo "of_node=$(readlink -f "$n/of_node" 2>/dev/null)"
    for f in "$n"/*; do
      echo "--- $f ---"
      cat "$f" 2>&1 | head -120
    done
  done
} > "$OUT/onewire-sysfs.txt" 2>&1

dump_dt_node() {
  node="$1"
  label="$2"
  {
    echo "=== $node ==="
    find "$node" -maxdepth 2 -type f 2>/dev/null | while read f; do
      rel="${f#$node/}"
      echo "--- $rel ---"
      case "$(basename "$f")" in
        compatible|name|label|pinctrl-names|status)
          tr '\000' '\n' < "$f" 2>&1
          ;;
        *)
          od -An -v -tx1 "$f" 2>&1
          ;;
      esac
    done
  } > "$OUT/dt-$label.txt" 2>&1
}

dump_dt_node /proc/device-tree/soc/onewire_gpio onewire_gpio
dump_dt_node /proc/device-tree/soc/onewire_slave_gpio onewire_slave_gpio

find /proc/device-tree -iname '*onewire*' -o -iname '*nano*' -o -iname '*keyboard*' -o -iname '*pogo*' -o -iname '*dock*' \
  > "$OUT/devicetree-search.txt" 2>&1

for d in /sys/devices/0006:15D9:*; do
  [ -e "$d" ] || continue
  base="$(basename "$d")"
  mkdir -p "$OUT/hid/$base"
  {
    echo "path=$d"
    echo "driver=$(readlink -f "$d/driver" 2>/dev/null)"
    cat "$d/uevent" 2>/dev/null
    echo "modalias=$(cat "$d/modalias" 2>/dev/null)"
    echo "country=$(cat "$d/country" 2>/dev/null)"
  } > "$OUT/hid/$base/info.txt" 2>&1
  cat "$d/report_descriptor" > "$OUT/hid/$base/report_descriptor.bin" 2>/dev/null
  od -An -v -tx1 "$d/report_descriptor" > "$OUT/hid/$base/report_descriptor.hex" 2>/dev/null
done

dmesg | grep -iE 'nano|nanosic|nanodev|onewire|keyboard|pogo|dock|hid|15d9|00a3|00a1|uinput' \
  > "$OUT/dmesg-keyboard.txt" 2>&1
logcat -d | grep -iE 'nano|nanosic|nanodev|onewire|keyboard|pogo|dock|hid|15d9|00a3|00a1|uinput|keyboardnano' \
  > "$OUT/logcat-keyboard.txt" 2>&1
cat /proc/interrupts | grep -iE 'nano|onewire|keyboard|gpio|hid|i2c|spi' \
  > "$OUT/proc-interrupts.txt" 2>&1

cp /vendor/bin/hw/vendor.xiaomi.hardware.keyboardnanoapp@1.0-service "$OUT/bin/" 2>/dev/null || true
cp /vendor/lib64/vendor.xiaomi.hardware.keyboardnanoapp@1.0.so "$OUT/bin/" 2>/dev/null || true
cp /vendor/etc/Keyboard_Upgrade_0x*.bin "$OUT/bin/" 2>/dev/null || true
cp /system_ext/lib64/libhidconverter.so "$OUT/bin/" 2>/dev/null || true
cp /system_ext/etc/input/MIUIInput.kl "$OUT/bin/" 2>/dev/null || true

chmod -R 755 "$OUT"
echo "$OUT"

