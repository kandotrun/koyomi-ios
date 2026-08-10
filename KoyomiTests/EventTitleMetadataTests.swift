import Foundation
import Testing
@testable import KoyomiCore

@Suite("予定タイトルのタグ")
struct EventTitleMetadataTests {
    @Test("タグを本文から分離して表示順を保つ")
    func separatesTagsFromDisplayTitle() {
        let metadata = EventTitleMetadata.parse("ClinicalAIのレビュー #仕事 #タスク")

        #expect(metadata.displayTitle == "ClinicalAIのレビュー")
        #expect(metadata.tags == ["仕事", "タスク"])
    }

    @Test("先頭タグと重複タグを扱う")
    func handlesLeadingAndDuplicateTags() {
        let metadata = EventTitleMetadata.parse("#重要 出産準備 #重要 #IMPORTANT #important")

        #expect(metadata.displayTitle == "出産準備")
        #expect(metadata.tags == ["重要", "IMPORTANT"])
    }

    @Test("C sharpや単語内のシャープをタグと誤認しない")
    func doesNotTreatEmbeddedSharpAsTag() {
        let metadata = EventTitleMetadata.parse("C# APIレビューと価格#確認")

        #expect(metadata.displayTitle == "C# APIレビューと価格#確認")
        #expect(metadata.tags.isEmpty)
    }

    @Test("タグ末尾の句読点を本文に残さない")
    func trimsTrailingPunctuation() {
        let metadata = EventTitleMetadata.parse("確認 #タスク、 #重要。")
        let leadingPunctuation = EventTitleMetadata.parse("Meeting #.NET")
        let ellipsis = EventTitleMetadata.parse("確認 #仕事…")

        #expect(metadata.displayTitle == "確認")
        #expect(metadata.tags == ["タスク", "重要"])
        #expect(leadingPunctuation.displayTitle == "Meeting")
        #expect(leadingPunctuation.tags == [".NET"])
        #expect(ellipsis.tags == ["仕事"])
    }

    @Test("タグしかない予定には読み上げ可能な代替タイトルを付ける")
    func suppliesUntitledFallback() {
        let metadata = EventTitleMetadata.parse("#メモ　#重要")

        #expect(metadata.displayTitle == "無題の予定")
        #expect(metadata.tags == ["メモ", "重要"])
    }

    @Test("タグの一致判定は大文字小文字と全半角を無視する")
    func matchesTagForMetadataDeduplication() {
        let metadata = EventTitleMetadata.parse("設計 #仕事 #ＡＩ")

        #expect(metadata.containsTag("仕事"))
        #expect(metadata.containsTag("ai"))
        #expect(!metadata.containsTag("個人"))
    }

    @Test("任意のプロジェクトタグで絞り込める")
    func filtersEventsByArbitraryTag() {
        let events = [
            makeEvent(id: "1", title: "設計レビュー #仕事 #ClinicalAI"),
            makeEvent(id: "2", title: "API修正 #タスク #clinicalai"),
            makeEvent(id: "3", title: "買い物 #タスク #個人"),
        ]

        #expect(EventTagIndex.events(from: events, matching: "CLINICALAI").map(\.id) == ["1", "2"])
        #expect(EventTagIndex.events(from: events, matching: nil) == events)
    }

    @Test("基本タグを先にし、任意タグは名前順で並べる")
    func ordersAvailableTagsPredictably() {
        let events = [
            makeEvent(id: "1", title: "A #仕事 #Zeta"),
            makeEvent(id: "2", title: "B #タスク #alpha"),
            makeEvent(id: "3", title: "C #重要 #メモ #Beta"),
        ]

        #expect(EventTagIndex.tags(in: events) == ["重要", "タスク", "仕事", "メモ", "alpha", "Beta", "Zeta"])
    }

    @Test("利用不能になった選択タグは解除し、表記揺れは現在のタグ名へ寄せる")
    func resolvesSelectionAgainstAvailableTags() {
        #expect(
            EventTagIndex.resolvedSelection("ＡＩ", availableTags: ["仕事", "ai"])
                == "ai"
        )
        #expect(EventTagIndex.resolvedSelection("個人", availableTags: ["仕事", "タスク"]) == nil)
        #expect(EventTagIndex.resolvedSelection("AI", availableTags: ["仕事"]) == nil)
        #expect(EventTagIndex.resolvedSelection(nil, availableTags: ["仕事"]) == nil)
    }

    @Test("同じタグidentityは表記揺れにかかわらず同じpalette indexを使う")
    func normalizesStablePaletteIndex() {
        let canonical = EventTagIndex.stablePaletteIndex(for: "ClinicalAI", paletteCount: 5)

        #expect(EventTagIndex.stablePaletteIndex(for: "clinicalai", paletteCount: 5) == canonical)
        #expect(EventTagIndex.stablePaletteIndex(for: "ＣｌｉｎｉｃａｌＡＩ", paletteCount: 5) == canonical)
        #expect(EventTagIndex.stablePaletteIndex(for: "ClinicalAI", paletteCount: 0) == 0)
    }

    @Test("Reduce Motion有効時はタグ切替をanimationしない")
    func respectsReduceMotionForTagFiltering() {
        #expect(EventTagAnimationPolicy.shouldAnimate(reduceMotionEnabled: false))
        #expect(!EventTagAnimationPolicy.shouldAnimate(reduceMotionEnabled: true))
    }

    @Test("表示用タイトルを分離しても元タイトルとピン情報は保持する")
    func keepsRawCalendarTitleInSnapshot() {
        let event = makeEvent(id: "1", title: "設計レビュー #仕事 #ClinicalAI")

        #expect(event.titleMetadata.displayTitle == "設計レビュー")
        #expect(event.titleMetadata.tags == ["仕事", "ClinicalAI"])
        #expect(event.pinnedSnapshot.title == "設計レビュー #仕事 #ClinicalAI")
        #expect(event.pinnedSnapshot.titleMetadata.displayTitle == "設計レビュー")
    }

    private func makeEvent(id: String, title: String) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        return CalendarEvent(
            id: id,
            eventIdentifier: "event-\(id)",
            externalIdentifier: "external-\(id)",
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "work",
            calendarName: "仕事",
            calendarColorHex: "5B8DEF",
            location: nil
        )
    }
}
