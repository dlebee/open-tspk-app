#!/bin/bash
# Captures store screenshots while integration_test/store_screenshots_test.dart runs.
# Usage: tool/store_screenshots.sh ios <simulator-udid> <out-dir>
#        tool/store_screenshots.sh android <adb-serial> <out-dir>
# Wipes the app's data on that device: test devices only.
# The test names each shot in the app's Documents/shot_marker.txt (iOS buffers
# test logs, so the log line arrives too late there) and prints "[shot] name".
set -u
platform=$1; device=$2; out=$3
bundle=com.davidlebee.thygeson
mkdir -p "$out"
log=$(mktemp)
if [ "$platform" = ios ]; then
  c=$(xcrun simctl get_app_container "$device" $bundle data 2>/dev/null) && rm -f "$c/Documents/shot_marker.txt"
fi
flutter test integration_test/store_screenshots_test.dart -d "$device" > "$log" 2>&1 &
pid=$!
seen=""
current() {
  if [ "$platform" = ios ]; then
    c=$(xcrun simctl get_app_container "$device" $bundle data 2>/dev/null) && cat "$c/Documents/shot_marker.txt" 2>/dev/null
  else
    grep -o '\[shot\] [0-9a-z-]*' "$log" | tail -1 | awk '{print $2}'
  fi
}
while kill -0 $pid 2>/dev/null; do
  name=$(current)
  if [ -n "$name" ]; then
    case " $seen " in *" $name "*) ;; *)
      seen="$seen $name"
      sleep 1
      if [ "$platform" = ios ]; then
        xcrun simctl io "$device" screenshot "$out/$name.png" >/dev/null 2>&1
      else
        adb -s "$device" exec-out screencap -p > "$out/$name.png"
      fi
      echo "captured $name"
      case "$name" in 07-*) sleep 3; kill $pid 2>/dev/null;; esac
    esac
  fi
  sleep 0.5
done
wait $pid 2>/dev/null
tail -3 "$log"
