# 私と音楽

1日1曲、その日の音楽を記録する iOS アプリ。V-Diary の「今日の音楽」から生まれた姉妹アプリです。

- Apple Music のカタログから曲を検索・試聴（約30秒）して、その日の一曲に選ぶ
- ひとことメモ
- ジャケットが並ぶカレンダー
- ふりかえり（月・年ごとの曲一覧、よく選んだアーティスト、連続記録）
- 毎日のリマインダー
- V-Diary と同じテーマカラー・背景パターン・ダークモード・日本語／英語

選んだ曲（曲名・アーティスト・ジャケット URL・試聴 URL）とメモは端末内（SwiftData）に保存します。
Apple Music の契約がなくても検索と試聴は使えます。App ID で MusicKit を有効にする必要があります。

## 開発

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # Team ID と Bundle ID の接頭辞
xcodegen generate
open WatashiToOngaku.xcodeproj
```

| コマンド | 内容 |
|---|---|
| `scripts/screenshots.sh` | サンプルデータで起動して App Store 用スクリーンショットを撮る |
| `swift tools/make_icon.swift <V-Diaryのappiconset> <出力>` | V-Diary のアイコンに音符を重ねてアイコンを作る |
| 起動引数 `-uiPreview -initialTab calendar` | メモリ上のサンプルデータで起動 |

## クレジット

- 「今日」のアイコン: [Music icon by dickprayuda – Flaticon](https://www.flaticon.com/free-icon/music_10848925)（Flaticon License、要クレジット表記）
