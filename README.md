# こよみ — Koyomi

![Core tests](https://github.com/kandotrun/koyomi-ios/actions/workflows/core-tests.yml/badge.svg)
![iOS app](https://github.com/kandotrun/koyomi-ios/actions/workflows/ios.yml/badge.svg)

予定を眺めるための、iOS 26以降向け個人カレンダービューアです。
大切な予定をピン留めし、開始・終了までをアプリとホーム／ロック画面ウィジェットで確認できます。

![Koyomi home screen](docs/koyomi-home.png)

## できること

- EventKitでiPhoneに登録済みのカレンダーを閲覧
- 終日・時間指定・日をまたぐ予定を日付ごとに表示
- 予定のピン留め／解除
- ピン留めを画面上部に常設し、開始前は「あと」、進行中は「終了まで」を秒単位で表示
- 複数ピンを横スクロールで確認
- 日付ストリップ、グラフィカル日付選択、今日へ移動、プル更新
- Small / Mediumホーム画面ウィジェット
- accessory rectangularロック画面ウィジェット
- ピンした予定をウィジェットから開くディープリンク
- iOS 26のLiquid Glass。ガラスはピン領域と操作部に絞り、Reduce Transparency時は不透明度の高い代替表示

Googleカレンダーも、iOSの「カレンダー」に同期済みであればEventKit経由で表示されます。

## データとプライバシー

- バックエンド、ログイン、分析SDK、外部通信はありません。
- カレンダー内容を端末外へ送信しません。
- App Groupに保存するのは、ユーザーがピン留めした予定の表示用スナップショットだけです。
- スナップショットにはタイトル、開始・終了、終日フラグ、カレンダー名・色、場所を含みます。メモ、参加者、URL、アラームは保存しません。
- Widget extensionはEventKitへ直接アクセスせず、共有スナップショットだけを読みます。
- カレンダー権限は初回画面のボタンを押したときに要求します。拒否・制限・書き込み専用の各状態には個別の案内があります。

## 必要環境

- macOS 26
- Xcode 26.6
- iOS 26.0以降のiPhone
- App Groupsを有効化できるApple Developer Team

## 開発

`Koyomi.xcodeproj`はコミット済みです。構成を変更した場合はXcodeGenで再生成できます。

```bash
brew install xcodegen
xcodegen generate
open Koyomi.xcodeproj
```

コアロジックだけをテストする場合:

```bash
swift test
```

CIはGitHub-hosted `macos-26` / Xcode 26.6で、Swift Packageのユニットテスト、iOS Simulatorビルド、UIテスト、デモ画面のスクリーンショット取得まで実行します。

## 実機署名

初回のみ、Xcodeの **Signing & Capabilities** で次を設定します。

1. `Koyomi` と `KoyomiWidget` のTeamを同じApple Developer Teamへ変更する。
2. App Groups capabilityを両ターゲットで有効化する。
3. `group.run.kan.koyomi` をDeveloper Portalへ登録し、両ターゲットへ追加する。
4. Bundle ID `run.kan.koyomi` と `run.kan.koyomi.widget` が自分のTeamで使えない場合は、`project.yml`、両entitlements、`KoyomiAppGroup.identifier`を同じ新しい識別子へ変更して `xcodegen generate` を実行する。
5. iPhoneを接続して `Koyomi` schemeをRunする。

署名用Team IDや証明書はリポジトリに固定していません。

## 構成

- `Shared/` — 予定スナップショット、カウントダウン、ピン永続化、日付範囲・再照合ロジック
- `Koyomi/` — EventKitアダプター、状態管理、Liquid Glass UI
- `KoyomiWidget/` — App Groupを読むWidgetKit extension
- `KoyomiTests/` — Foundation中心のユニットテスト
- `KoyomiUITests/` — 権限不要のデモデータを使うUIテスト

WidgetKitのタイムライン更新時刻はシステムが最終決定します。表示中のカウントダウン自体はSwiftUIのタイマーテキストで進み、開始・終了境界ではタイムライン更新を要求します。
