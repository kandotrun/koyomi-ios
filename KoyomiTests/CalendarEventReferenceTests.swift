import Foundation
import Testing
@testable import KoyomiCore

@Suite("Calendar予定の厳密一致")
struct CalendarEventReferenceTests {
    @Test("同じ予定・Calendar・開始終了だけ一致する")
    func matchesExactOccurrence() {
        let original = makeEvent()
        let reference = CalendarEventReference(original)

        #expect(reference?.matches(original) == true)
        #expect(reference?.matches(makeEvent(startOffset: 86_400)) == false)
        #expect(reference?.matches(makeEvent(calendarID: "personal")) == false)
        #expect(reference?.matches(makeEvent(endOffset: 60)) == false)
    }

    @Test("eventIdentifierが同じ再発予定でも別occurrenceを拒否する")
    func rejectsAnotherRecurringOccurrence() {
        let original = makeEvent(eventIdentifier: "series-id")
        let another = makeEvent(eventIdentifier: "series-id", startOffset: 7 * 86_400)

        #expect(CalendarEventReference(original)?.matches(another) == false)
    }

    @Test("externalIdentifierなしでも同時刻の別予定をwildcard一致しない")
    func rejectsCoincidentEventWithoutExternalIdentifier() {
        let original = makeEvent(eventIdentifier: "event-a", externalIdentifier: nil)
        let coincident = makeEvent(eventIdentifier: "event-b", externalIdentifier: nil)

        #expect(CalendarEventReference(original)?.matches(coincident) == false)
    }

    @Test("識別子が欠ける予定は編集対象にできない")
    func rejectsUnaddressableEvent() {
        let event = makeEvent(eventIdentifier: "", externalIdentifier: nil)

        #expect(CalendarEventReference(event) == nil)
    }

    @Test("厳密一致が0件または複数ならfail closed")
    func resolvesExactlyOneCandidate() throws {
        let original = makeEvent()
        let reference = try #require(CalendarEventReference(original))

        #expect(try reference.resolve(in: [original]) == original)
        #expect(throws: CalendarEventReferenceError.notFound) {
            try reference.resolve(in: [makeEvent(startOffset: 86_400)])
        }
        #expect(throws: CalendarEventReferenceError.ambiguous) {
            try reference.resolve(in: [original, original])
        }
    }

    private func makeEvent(
        eventIdentifier: String = "event-a",
        externalIdentifier: String? = "external-a",
        calendarID: String = "work",
        startOffset: TimeInterval = 0,
        endOffset: TimeInterval = 0
    ) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_750_000_000 + startOffset)
        return CalendarEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: eventIdentifier,
                externalIdentifier: externalIdentifier,
                startDate: start
            ),
            eventIdentifier: eventIdentifier,
            externalIdentifier: externalIdentifier,
            title: "定例 #仕事",
            startDate: start,
            endDate: start.addingTimeInterval(3_600 + endOffset),
            isAllDay: false,
            calendarID: calendarID,
            calendarName: calendarID,
            calendarColorHex: "5B8DEF",
            location: nil
        )
    }
}
