# AGENTS.md

## Product contract

Koyomi（表示名「こよみ」）は、iOS 26以降向けの端末内完結カレンダー／タスク管理アプリです。
EventKitを正本として予定と`#タスク`を表示・作成・編集・完了・複製・削除し、選んだ予定をアプリとWidgetKitウィジェットでカウントダウン表示します。
予定名の空白区切り`#タグ`は本文と分離して表示・検索・絞り込みし、ユーザーが明示的に保存したときだけEventKitへ差分を書き戻します。
バックエンド、アカウント、分析SDKは追加しません。

## Engineering rules

1. 新しい挙動は RED → GREEN → REFACTOR。先に失敗するテストを追加し、その失敗を確認する。
2. カウントダウン・ピン選択・保存・日付境界は `KoyomiCore` の純粋ロジックとしてテストする。
3. EventKitは `@MainActor` のアダプタに閉じ込める。unit/Preview/UIテストはサンプルデータ源を使い、EventKit統合テストは専用の一時ローカルCalendarだけを作成して必ず後始末する。
4. iOSアプリがEventKitから取得したCalendar内容は端末外へ送らない。ログにもタイトル、場所、参加者、URLを出さない。
5. 共有Keychainに保存するのはピン留めした予定の表示スナップショットだけ。
6. Liquid Glassは標準ナビゲーション・ツールバーを優先し、カスタムglassEffectを乱用しない。
7. VoiceOver、文字サイズ、Reduce Motion、Reduce Transparency、ダークモードを壊さない。
8. iOS deployment targetは26.0。Swift 6の警告を放置しない。
9. タグ処理は`EventTitleMetadata`と`EventTitleTagMutator`に集約し、ユーザーの明示保存時だけ最新raw titleへadd/remove差分を適用する。未知タグを保持し、変更後は該当ピンとWidgetを同期する。
10. Hermes連携はGoogle Calendarを正本とするアプリ外の運用境界に置き、トークンやagent endpointをiOSアプリへ埋め込まない。

タグ記法とHermes運用契約は`docs/calendar-title-tags.md`を参照してください。

## Verification

```bash
swift test --parallel
xcodegen generate
xcodebuild test -project Koyomi.xcodeproj -scheme Koyomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Koyomi.xcodeproj -scheme Koyomi -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

CIはGitHub-hosted `macos-26` / Xcode 26.6を使います。
