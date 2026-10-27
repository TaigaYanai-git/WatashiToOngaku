#!/bin/zsh
# アイコンを選ぶ画面の見本に使う画像を、Icon Composer の .icon から書き出す（アイコンを作り直したら実行する）
set -e
cd "$(dirname "$0")/.."
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
ASSETS=WatashiToOngaku/Resources/Assets.xcassets
for icon in WatashiToOngaku/AppIcon.icon WatashiToOngaku/ThemeIcons/*.icon; do
  name=$(basename "$icon" .icon)
  set=$ASSETS/IconPreview-$name.imageset
  mkdir -p "$set"
  "$ICTOOL" "$icon" --export-image --output-file "$set/$name.png" --platform iOS --rendition Default --width 64 --height 64 --scale 3
  cat > "$set/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$name.png", "idiom" : "universal", "scale" : "3x" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done
