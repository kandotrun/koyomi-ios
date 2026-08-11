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
| `#タスク` | Actionable work |
| `#完了` | Completed task; meaningful only with `#タスク` |
| `#見込み` | `#タスク`と併用する日付未確定の見込み期間。終日帯の開始が最早日、排他的終了日の前日が最遅日 |
| `#仕事` | Work context |
| `#メモ` | Something to remember or revisit |

Project and context tags are intentionally open-ended, for example `#ClinicalAI`, `#KOTOBUKI`, `#TeslaEC`, `#家族`, or `#旅行`.

`#重要`だけでは自動ピンしません。通常予定のピン留めは明示的な端末内操作です。新規の`#見込み #タスク`だけは「忘れない」目的に合わせてKoyomiが作成直後に自動ピンします。ユーザーはいつでも解除できます。

## Estimated date windows

日付が未確定のタスクは、別データベースや非公開メタデータを使わず、Calendarだけで往復できる形にします。

- ユーザー入力は「目安日」と「前後の幅」。専用追加導線の既定値は選択日の1か月後、前後14日です。
- EventKitには最早日から最遅日までの複数日終日予定として保存します。`endDate`は最遅日の翌日0:00で排他的です。
- タイトルに`#タスク #見込み`を付けます。`#重要`と任意タグも通常どおり併用できます。`#タスク`のない`#見込み`は通常の任意タグとして扱います。
- 見込み期間は左右対称の単発タスクに限定し、繰り返し設定とは併用しません。
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
- Widget snapshots update immediately after a successful mutation but still exclude notes, attendees, URLs, and alarms.
