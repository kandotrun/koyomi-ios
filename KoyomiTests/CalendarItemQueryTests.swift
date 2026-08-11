import Foundation
import Testing
@testable import KoyomiCore

@Suite("予定・タスク検索")
struct CalendarItemQueryTests {
    private let events = [
        makeQueryEvent(title: "設計レビュー #会議", location: "オンライン", notes: "APIを確認"),
        makeQueryEvent(id: "task-open", title: "請求書 #タスク #重要", location: nil, notes: "顧客A"),
        makeQueryEvent(id: "task-done", title: "発送 #タスク #完了 #買物", location: "広島", notes: nil)
    ]

    @Test("タイトル・タグ・場所・メモを正規化検索する")
    func searchesAllVisibleFields() {
        #expect(CalendarItemQuery.events(from: events, searchText: "レビュー", filter: .all).map(\.id) == ["event"])
        #expect(CalendarItemQuery.events(from: events, searchText: "会議", filter: .all).map(\.id) == ["event"])
        #expect(CalendarItemQuery.events(from: events, searchText: "オンライン", filter: .all).map(\.id) == ["event"])
        #expect(CalendarItemQuery.events(from: events, searchText: "ａｐｉ", filter: .all).map(\.id) == ["event"])
        #expect(CalendarItemQuery.events(from: events, searchText: "顧客A", filter: .all).map(\.id) == ["task-open"])
    }

    @Test("予定・未完了タスク・完了タスクを分ける")
    func filtersKindsAndCompletion() {
        #expect(CalendarItemQuery.events(from: events, searchText: "", filter: .events).map(\.id) == ["event"])
        #expect(CalendarItemQuery.events(from: events, searchText: "", filter: .openTasks).map(\.id) == ["task-open"])
        #expect(CalendarItemQuery.events(from: events, searchText: "", filter: .completedTasks).map(\.id) == ["task-done"])
    }

    @Test("見込み期間だけを専用フィルターで抽出する")
    func filtersEstimatedWindows() {
        var estimated = makeQueryEvent(
            id: "estimated",
            title: "指輪の刻印 #タスク #見込み",
            location: nil,
            notes: nil
        )
        estimated.isAllDay = true
        estimated.endDate = estimated.startDate.addingTimeInterval(29 * 86_400)

        #expect(
            CalendarItemQuery.events(
                from: events + [estimated],
                searchText: "",
                filter: .estimatedWindows
            ).map(\.id) == ["estimated"]
        )
    }
}

private func makeQueryEvent(
    id: String = "event",
    title: String,
    location: String?,
    notes: String?
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        eventIdentifier: id,
        externalIdentifier: nil,
        title: title,
        startDate: Date(timeIntervalSince1970: 1_750_000_000),
        endDate: Date(timeIntervalSince1970: 1_750_003_600),
        isAllDay: false,
        calendarID: "work",
        calendarName: "仕事",
        calendarColorHex: "5B8DEF",
        location: location,
        notes: notes
    )
}
