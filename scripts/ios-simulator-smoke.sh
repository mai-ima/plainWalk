#!/bin/bash
set -euo pipefail
PW_SIM_DEVICE=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; data=json.load(sys.stdin); devices=[d for values in data["devices"].values() for d in values if "iPhone" in d["name"] and d.get("isAvailable")]; print(devices[0]["udid"] if devices else "")')
if [[ -z "$PW_SIM_DEVICE" ]]; then
  echo "No available iPhone simulator runtime."
  exit 1
fi
xcrun simctl boot "$PW_SIM_DEVICE" || true
xcrun simctl bootstatus "$PW_SIM_DEVICE" -b
PW_APP_PATH="$PWD/.build/ios/Build/Products/Debug-iphonesimulator/PlainWalk.app"
xcrun simctl install "$PW_SIM_DEVICE" "$PW_APP_PATH"
xcrun simctl launch "$PW_SIM_DEVICE" org.example.plainwalkweb -PlainWalkSmokeTest
PW_APP_CONTAINER=$(xcrun simctl get_app_container "$PW_SIM_DEVICE" org.example.plainwalkweb data)
PW_READY_FILE="$PW_APP_CONTAINER/Library/Application Support/PlainWalk/native-ready.json"
for PW_ATTEMPT in $(seq 1 30); do
  if [[ -f "$PW_READY_FILE" ]]; then
    python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); assert data.get("ready") is True and data.get("recordingPersistence") is True and data.get("nativeUI") is True and data.get("storage") is True and data.get("trackMath") is True and data.get("trackIO") is True; print("Native SwiftUI application, storage, track import and recorder recovery checks passed on iOS Simulator.")' "$PW_READY_FILE"
    mkdir -p .build/screenshots
    xcrun simctl io "$PW_SIM_DEVICE" screenshot .build/screenshots/ios-native-map.png
    xcrun simctl terminate "$PW_SIM_DEVICE" org.example.plainwalkweb
    xcrun simctl launch "$PW_SIM_DEVICE" org.example.plainwalkweb -PlainWalkSmokeTest -PlainWalkNativeSettingsSmokeTest
    for PW_SETTINGS_ATTEMPT in $(seq 1 20); do
      if [[ -f "$PW_APP_CONTAINER/Library/Application Support/PlainWalk/native-settings-ready.json" ]]; then
        xcrun simctl io "$PW_SIM_DEVICE" screenshot .build/screenshots/ios-native-settings.png
        exit 0
      fi
      sleep 1
    done
    echo "Native settings did not become ready."
    exit 1
  fi
  sleep 1
done
xcrun simctl spawn "$PW_SIM_DEVICE" log show --last 2m --style compact --predicate 'process == "PlainWalk"' || true
echo "The native UI did not reach its ready state."
exit 1
