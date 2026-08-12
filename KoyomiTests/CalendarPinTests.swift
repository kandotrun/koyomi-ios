import Foundation
import Testing
@testable import KoyomiCore

@Suite("Calendarタイトルを正本にするピン")
struct CalendarPinTests {
    @Test("EventKitの4年上限内で未来を優先してピンを探索する")
    func usesFourYearDiscoveryWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let anchor = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 12
        )))
        let interval = try #require(CalendarPin.discoveryInterval(
            around: anchor,
            calendar: calendar
        ))

        #expect(interval.start == calendar.date(byAdding: .month, value: -6, to: anchor))
        #expect(interval.end == calendar.date(byAdding: .month, value: 42, to: anchor))
    }

    @Test("空白区切りのピンタグだけをピンとして扱う")
    func recognizesOnlyPinTagTokens() {
        #expect(makeEvent(id: "1", title: "大切な予定 #ピン").isPinned)
        #expect(makeEvent(id: "2", title: "句読点付き #ピン。").isPinned)
        #expect(!makeEvent(id: "3", title: "ピン留めを検討").isPinned)
        #expect(!makeEvent(id: "4", title: "予定#ピン").isPinned)
    }

    @Test("Calendarイベントからピン付き予定だけを重複なく時系列で派生する")
    func derivesSnapshotsFromCalendarEvents() {
        let later = makeEvent(
            id: "later",
            title: "後の予定 #ピン",
            start: Date(timeIntervalSince1970: 300)
        )
        let ignored = makeEvent(
            id: "ignored",
            title: "通常予定",
            start: Date(timeIntervalSince1970: 200)
        )
        var earlier = makeEvent(
            id: "earlier",
            title: "前の予定 #ピン",
            start: Date(timeIntervalSince1970: 100)
        )
        var updatedEarlier = earlier
        updatedEarlier.title = "更新後の予定 #ピン #仕事"
        earlier.title = "更新前の予定 #ピン"

        let snapshots = CalendarPin.snapshots(
            from: [later, ignored, earlier, updatedEarlier]
        )

        #expect(snapshots.map(\.eventIdentifier) == ["event-earlier", "event-later"])
        #expect(snapshots.first?.title == "更新後の予定 #ピン #仕事")
    }

    @Test("繰り返し予定は同じseriesごとに将来32件までをWidgetキャッシュへ派生する")
    func boundsRecurringSeriesSnapshots() {
        let now = Date(timeIntervalSince1970: 1_000)
        let recurring = (0..<100).map { offset in
            var event = makeEvent(
                id: "daily-\(offset)",
                title: "毎日の予定 #ピン",
                start: now.addingTimeInterval(TimeInterval(offset + 1) * 86_400)
            )
            event.externalIdentifier = "daily-series"
            event.isRecurring = true
            return event
        }

        let snapshots = CalendarPin.snapshots(from: recurring, at: now)

        #expect(snapshots.count == 32)
        #expect(snapshots.first?.startDate == recurring.first?.startDate)
        #expect(snapshots.last?.startDate == recurring[31].startDate)
    }

    private func makeEvent(
        id: String,
        title: String,
        start: Date = Date(timeIntervalSince1970: 100)
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            eventIdentifier: "event-\(id)",
            externalIdentifier: nil,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "calendar",
            calendarName: "Calendar",
            calendarColorHex: "5B8DEF",
            location: nil,
            canEdit: true
        )
    }
}
