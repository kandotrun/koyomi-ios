import XCTest
@testable import KoyomiCore

final class KoyomiHapticPolicyTests: XCTestCase {
    func testNavigationAndSelectionInteractionsUseSelectionFeedback() {
        let interactions: [KoyomiInteraction] = [
            .selectDate,
            .switchAgenda,
            .changeCalendarFilter,
            .openEvent,
            .refresh,
            .requestAccess,
            .dismiss
        ]

        for interaction in interactions {
            XCTAssertEqual(KoyomiHapticPolicy.feedback(for: interaction), .selection)
        }
    }

    func testPinChangesUseAVisibleImpact() {
        XCTAssertEqual(KoyomiHapticPolicy.feedback(for: .togglePin), .impact)
    }
}
