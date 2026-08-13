import ActivityKit
import Foundation
import XCTest
@testable import Koyomi

final class PinnedLiveActivityPayloadTests: XCTestCase {
    func testMaximumPolicyPayloadFitsBelowManagerSafetyLimit() throws {
        let attributes = PinnedEventActivityAttributes(
            eventID: String(
                repeating: "i",
                count: PinnedLiveActivityPolicy.maximumEventIDUTF8Bytes
            ),
            scheduledStartDate: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let state = PinnedEventActivityAttributes.ContentState(
            title: String(
                repeating: "\\\"",
                count: PinnedLiveActivityPolicy.maximumTitleUTF8Bytes / 2
            ),
            calendarName: String(
                repeating: "\\\"",
                count: PinnedLiveActivityPolicy.maximumCalendarNameUTF8Bytes / 2
            ),
            calendarColorHex: "5B8DEF",
            startDate: Date(timeIntervalSince1970: 2_000_000_000),
            isAllDay: false,
            isEstimatedDateWindow: false
        )

        let encoder = JSONEncoder()
        let payloadSize = try encoder.encode(attributes).count
            + encoder.encode(state).count

        XCTAssertLessThanOrEqual(payloadSize, 3_500)
        XCTAssertLessThan(payloadSize, 4_096)
    }
}
