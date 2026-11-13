#!/bin/bash
# Runs an integration test on a test device and answers the notification
# permission prompt that appears after each fresh install.
# Usage: tool/device_test.sh integration_test/<file>.dart <android-serial | ios-udid> [log-file]
set -u
test=$1; device=$2; log=${3:-/dev/stdout}
flutter test "$test" -d "$device" > "$log" 2>&1 &
pid=$!
if [[ "$device" == emulator-* ]]; then
  while kill -0 $pid 2>/dev/null; do
    if adb -s "$device" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 &&
       adb -s "$device" shell cat /sdcard/ui.xml 2>/dev/null | grep -q permission_allow_button; then
      b=$(adb -s "$device" shell cat /sdcard/ui.xml | grep -o 'permission_allow_button"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]')
      read x1 y1 x2 y2 <<<"$(echo "$b" | sed 's/\]\[/,/; s/[][]//g' | tr ',' ' ')"
      adb -s "$device" shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 ))
      break
    fi
    sleep 3
  done
fi
wait $pid
