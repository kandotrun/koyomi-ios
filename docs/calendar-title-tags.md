# Calendar title tags and Hermes operations

Koyomi treats the calendar as the source of truth. It does not create a second task database or upload EventKit data to an application backend.

## Title convention

Write a readable title first and append whitespace-delimited hashtags:

```text
ClinicalAI 定例 #仕事 #ClinicalAI
請求書を送る #タスク #重要 #TeslaEC
あとで調べる：音声UI #メモ #AI
```

Koyomi displays the readable title separately from the tags. It only changes the calendar title after an explicit save or task-completion action, and applies tag changes to the latest EventKit title without deleting unknown tags.

Rules:

- A tag starts with `#` at the beginning of a whitespace-delimited token.
- `C#` and `価格#確認` are ordinary title text, not tags.
- Duplicate tags are collapsed for display without changing the source title.
- Matching ignores case, width, and diacritics.
- Unknown tags are valid project or context tags.
- The first release filters by one tag at a time.

## Recommended base vocabulary

| Tag | Meaning |
| --- | --- |
| `#重要` | Needs prominent attention |
| `#ピン` | アプリとWidgetに常設するカウントダウン対象。ピン状態の正本 |
| `#タスク` | Actionable work |
| `#完了` | Completed task; meaningful only with `#タスク` |
| `#見込み` | `#タスク`と併用する日付未確定の見込み期間。終日帯の開始が最早日、排他的終了日の前日が最遅日 |
| `#仕事` | Work context |
| `#メモ` | Something to remember or revisit |

Project and context tags are intentionally open-ended, for example `#ClinicalAI`, `#KOTOBUKI`, `#TeslaEC`, `#家族`, or `#旅行`.

`#重要`だけでは自動ピンしません。通常予定は、予定名へ`#ピン`を付けるかKoyomiのピン操作で同じタグを書き戻すとピン留めされます。新規の`#見込み #タスク`だけは「忘れない」目的に合わせてKoyomiが作成直後に`#ピン`を追加します。ユーザーはCalendarまたはKoyomiからいつでも解除できます。

ピン状態をUserDefaultsやKeychainの独自フラグには持ちません。Calendar予定名の`#ピン`だけが正本です。WidgetはEventKitへ直接アクセスしないため、Koyomiが現在の`#ピン`予定から派生させた最小表示スナップショットを共有Keychainへ保存します。このキャッシュはピン判定には使いません。旧版の`pinned-events-v1`はアップグレード時の移行候補としてのみ読みます。対応予定を一意に特定できた候補は、旧Keychain／UserDefaultsを同じ移行状態へ更新できた場合だけCalendar予定へ`#ピン`を書き戻します。fallbackを先にstageしてprimaryでcommitし、commit失敗時は旧primaryからfallbackを復元します。EventKit書込が失敗した場合はCalendarを再照合し、`#ピン`が未反映なら候補を移行キューへ戻し、書込済みなら成功として消費することで、一時エラーによるdata lossと書込後エラーによる再復活を避けます。

EventKitは1回の予定検索を最大4年へ制限するため、Koyomiは現在から過去6か月・未来42か月を全Calendar横断で探索します。探索窓外でも一度把握したピンは、キャッシュを候補IDとしてだけ使って該当日時をEventKitへ再照合し、現在の予定名に`#ピン`が残っている場合だけ表示を継続します。旧ピン移行で探索窓外の予定へ`#ピン`を書き戻せた場合は、そのEventKit返却値を同じ再読込の派生候補へ含め、v2表示キャッシュから脱落させません。EventKitの`eventIdentifier`が変わっても、同じ日時の`externalIdentifier`候補が一意なら再接続します。日時移動後の近傍再接続は、`eventIdentifier`または`externalIdentifier`が一致する単発予定だけに限定し、同じidentifierを共有し得る繰り返し予定はexact一致しなければfail closedにします。新規端末で探索窓外の`#ピン`を見つけるには、その日付を一度表示します。

繰り返し予定へ`#ピン`を付けた場合、4年分の全occurrenceをKeychainへ保存せず、同じCalendar・seriesごとに現在以降を優先して最大32件へ制限します。完全表現可能な無期限または終了日指定のdaily／weekly／monthly／yearly系列は、Calendar由来の再発ルール、観測済みanchor、4年探索区間で連続性を確認できた終端を表示キャッシュへ添付し、Widgetプロセス内でその終端まで次の最大32件を補充します。探索区間内に削除・移動・個別の`#ピン`解除・タイトルや時間の変更が1件でもあれば系列全体の補充をfail closedにし、Calendarの例外occurrenceを基礎ルールから復活させません。検証終端を持たない旧キャッシュ、回数終了型、高度なEventKitルールも終了境界を推測しません。繰り返し予定のピン留め・解除では「この予定のみ／これ以降すべて」を選び、選択前はCalendarを書き換えません。Widgetのcold deep linkは合成した将来occurrenceも候補としてCalendar再読込まで保留し、キャッシュだけを根拠に詳細やピン状態を確定しません。読み取り専用Calendarの予定は閲覧できますが、Calendarタイトルを書き換えられないため、ピン留め・解除操作を表示しません。

## Estimated date windows

日付が未確定のタスクは、別データベースや非公開メタデータを使わず、Calendarだけで往復できる形にします。

- ユーザー入力は「目安日」と「前後の幅」。専用追加導線の既定値は選択日の1か月後、前後14日です。
- EventKitには最早日から最遅日までの複数日終日予定として保存します。`endDate`は最遅日の翌日0:00で排他的です。
- タイトルに`#タスク #見込み`を付けます。`#重要`と任意タグも通常どおり併用できます。`#タスク`のない`#見込み`は通常の任意タグとして扱います。
- 見込み期間は左右対称の単発タスクに限定し、繰り返し設定とは併用しません。新規作成時は`#ピン`も追加します。
- Koyomiは秒カウントを出さず、「期間まで14日」「期間内・遅くとも14日」「3日超過」の日単位表示にします。
- 最遅日を過ぎても、未完了の見込みタスクは直近6か月まで「これから」に残します。自動ピンとWidgetは完了またはピン解除まで残り、`#完了`になったら注意表示から外れます。
- iOS 26のEventKitが終日終了を23:59:59で返す場合は、読み込み時に翌日0:00の排他的境界へ正規化します。

## Hermes boundary

Hermes may create, reschedule, or organize the connected Google Calendar when the user asks. It should:

1. Keep Google Calendar as the only shared source of truth.
2. Put the readable title first and tags at the end.
3. Preserve existing unknown tags when editing.
4. Use an explicit timezone for every timed event.
5. Show the proposed mutation and obtain user approval before creating, updating, moving, or deleting calendar events.
6. Never print raw calendar titles, descriptions, locations, attendees, or URLs in operational logs.

The iOS app remains offline-only. It uses EventKit full access for user-initiated create, update, completion, recurrence-scope, move, duplicate, and delete actions. It never contains a Hermes token, Google credential, or agent endpoint.

## Current capability

- Koyomi displays and edits tag chips across day, upcoming, detail, editor, pinned, and Widget surfaces.
- `#タスク` identifies a task; `#完了` records completion; `#重要` records priority. These remain ordinary Calendar title tags and sync through the calendar provider.
- Day and upcoming views support normalized search plus Calendar, type, completion, and tag filters.
- Mutations re-fetch the exact Calendar, occurrence start/end, and identifiers; zero or multiple matches fail closed.
- Read-only calendars, stale revisions, and unavailable recurrence scopes are rejected without mutation.
- `#ピン`はCalendar経由で同期され、アプリ外で追加・解除した変更も再読込時に反映されます。
- Widget snapshots are derived from current `#ピン` events after a successful refresh or mutation and still exclude notes, attendees, URLs, and alarms.
