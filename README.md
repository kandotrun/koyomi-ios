# こよみ — Koyomi

予定を眺めるための、iOS 26以降向け個人カレンダービューア。
大事な予定だけをピン留めし、開始・終了までをアプリとホーム／ロック画面ウィジェットで確認できます。

## MVP

- iPhoneのカレンダーをEventKitで読み込み（閲覧に必要なフルアクセスのみ）
- 日付ごとのアジェンダ表示
- 予定のピン留め／解除
- ピン留めした予定を画面上部に常設
- 開始前は「あと」、進行中は「終了まで」のライブカウントダウン
- Small / Medium / Lock Screen rectangularウィジェット
- iOS 26の標準コンポーネントとLiquid Glass
- オフライン・アカウント不要・分析SDKなし

## UX方針

純正カレンダーより「次に大事な時間」へ焦点を絞ります。
予定そのものを主役にし、Liquid Glassはピン領域と操作部に限定します。
背景は時刻に応じたごく薄い空の色、アクセントは予定元カレンダーの色を使います。

## データとプライバシー

- カレンダー内容をサーバーへ送信しません。
- App Groupには、ユーザーがピン留めした予定の表示用スナップショットだけを保存します。
- Widget extensionはEventKitへ直接アクセスせず、共有スナップショットを読みます。
- 権限を拒否した場合は設定への導線だけを表示します。

## 開発

Xcode 26.6、Swift 6、iOS 26.0以上。プロジェクトはXcodeGenで生成します。

```bash
brew install xcodegen
xcodegen generate
open Koyomi.xcodeproj
```

署名用のTeam IDはリポジトリに固定しません。実機導入時にXcodeでPersonal TeamまたはApple Developer Teamを選択します。
