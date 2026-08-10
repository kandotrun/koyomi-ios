# AGENTS.md

## Product contract

Koyomi（表示名「こよみ」）は、iOS 26以降向けの端末内完結カレンダービューアです。
EventKitの予定を読み、選んだ予定をピン留めし、アプリとWidgetKitウィジェットで開始・終了までを表示します。
バックエンド、アカウント、分析SDKは追加しません。

## Engineering rules

1. 新しい挙動は RED → GREEN → REFACTOR。先に失敗するテストを追加し、その失敗を確認する。
2. カウントダウン・ピン選択・保存・日付境界は `KoyomiCore` の純粋ロジックとしてテストする。
3. EventKitは `@MainActor` のアダプタに閉じ込め、テスト/Preview/UIテストではサンプルデータ源に差し替える。
4. Calendarの内容は端末外へ送らない。ログにもタイトル、場所、参加者、URLを出さない。
5. 共有Keychainに保存するのはピン留めした予定の表示スナップショットだけ。
6. Liquid Glassは標準ナビゲーション・ツールバーを優先し、カスタムglassEffectを乱用しない。
7. VoiceOver、文字サイズ、Reduce Motion、Reduce Transparency、ダークモードを壊さない。
8. iOS deployment targetは26.0。Swift 6の警告を放置しない。

## Verification

```bash
swift test --parallel
xcodegen generate
xcodebuild test -project Koyomi.xcodeproj -scheme Koyomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Koyomi.xcodeproj -scheme Koyomi -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

CIはGitHub-hosted `macos-26` / Xcode 26.6を使います。
