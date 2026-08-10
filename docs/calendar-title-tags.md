# Calendar title tags and Hermes operations

Koyomi treats the calendar as the source of truth. It does not create a second task database or upload EventKit data to an application backend.

## Title convention

Write a readable title first and append whitespace-delimited hashtags:

```text
ClinicalAI 定例 #仕事 #ClinicalAI
請求書を送る #タスク #重要 #TeslaEC
あとで調べる：音声UI #メモ #AI
```

Koyomi displays the readable title separately from the tags. The original calendar title remains unchanged.

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
| `#仕事` | Work context |
| `#メモ` | Something to remember or revisit |

Project and context tags are intentionally open-ended, for example `#ClinicalAI`, `#KOTOBUKI`, `#TeslaEC`, `#家族`, or `#旅行`.

`#重要` does not automatically pin an event. Pinning is an explicit, device-local action so an agent cannot silently override the user's pinned workspace.

## Hermes boundary

Hermes may create, reschedule, or organize the connected Google Calendar when the user asks. It should:

1. Keep Google Calendar as the only shared source of truth.
2. Put the readable title first and tags at the end.
3. Preserve existing unknown tags when editing.
4. Use an explicit timezone for every timed event.
5. Show the proposed mutation and obtain user approval before creating, updating, moving, or deleting calendar events.
6. Never print raw calendar titles, descriptions, locations, attendees, or URLs in operational logs.

The iOS app remains offline-only and read-only. Hermes is a separate operator that uses the calendar provider's API; there is no Hermes token, Google credential, or agent endpoint inside the app.

## Current capability

- Koyomi displays tag chips in day, upcoming, detail, and pinned surfaces.
- Day and upcoming views can be filtered by any discovered tag.
- Widgets parse the same raw title but display only the clean title to preserve space.
- Completion, waiting-state, and agent-driven pin synchronization are deliberately not inferred from tags yet.
