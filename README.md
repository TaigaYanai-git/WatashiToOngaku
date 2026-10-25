# Our Music

1日1曲、その日の音楽を記録する iOS アプリ。V-Diary の「今日の音楽」から生まれた姉妹アプリです。

- Apple Music のカタログから曲を検索・試聴（約30秒）して、その日の一曲に選ぶ。流す30秒の範囲も選べる（好きな位置から流すのは Apple Music の契約者だけ）
- ひとことメモ
- ジャケットが並ぶカレンダー
- ふりかえり（月・年ごとの曲一覧、よく選んだアーティスト、連続記録）
- 毎日のリマインダー
- フレンドのタイムラインと、みんなの今日のプレイリスト
- 自分の月・年・好きな期間（カスタム）のプレイリストを Apple Music で再生（順番／シャッフル）・ライブラリに保存
- Our Music Plus（カスタムカラー、1年のプレイリスト、31日より長いカスタムプレイリスト）
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
| `WatashiToOngaku/AppIcon.icon` | アプリアイコン（Icon Composer で開いて編集。レコードの盤とラベルの2層、どちらもガラス効果あり。外部素材は使わない） |
| 起動引数 `-uiPreview -initialTab calendar` | メモリ上のサンプルデータで起動 |

## クレジット

- 「今日」のアイコン: [Vinyl icon by Those Icons – Flaticon](https://www.flaticon.com/free-icon/vinyl_812680)（Flaticon License、要クレジット表記）
