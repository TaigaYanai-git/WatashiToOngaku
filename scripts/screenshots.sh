#!/bin/zsh
# App Store 用スクリーンショットをシミュレータで撮る（サンプルデータで起動）
#   scripts/screenshots.sh [デバイス名]   → screenshots/<デバイス名>/*.png
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-iPhone 17 Pro Max}"
OUT="screenshots/${DEVICE// /_}"
BUNDLE_ID=com.taigayanai.watashitoongaku
mkdir -p "$OUT"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl ui "$DEVICE" appearance "${APPEARANCE:-light}"

xcodebuild -project WatashiToOngaku.xcodeproj -scheme WatashiToOngaku -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build/screens -quiet build
xcrun simctl install "$DEVICE" build/screens/Build/Products/Debug-iphonesimulator/WatashiToOngaku.app

shoot() {  # 名前 起動引数...
  local name=$1; shift
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  # テーマカラーは THEME（ThemeStore.accents の番号）で選べる
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -uiPreview -dl_themeAccent "${THEME:-0}" -dl_bgPattern 1 "$@" >/dev/null
  sleep 3
  xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null
  echo "  $OUT/$name.png"
}

shoot 1_today -initialTab today
shoot 2_timeline -initialTab timeline
shoot 3_calendar -initialTab calendar
shoot 4_review -initialTab review
shoot 5_settings -initialTab settings
