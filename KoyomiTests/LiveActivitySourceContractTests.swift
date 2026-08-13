import Foundation
import XCTest

final class LiveActivitySourceContractTests: XCTestCase {
    func testProjectEnablesAndBundlesPinnedLiveActivities() throws {
        let project = try source(at: "project.yml")
        let bundle = try source(at: "KoyomiWidget/KoyomiWidget.swift")
        let app = try source(at: "Koyomi/KoyomiApp.swift")

        XCTAssertTrue(project.contains("NSSupportsLiveActivities: true"))
        XCTAssertTrue(bundle.contains("KoyomiPinnedEventLiveActivity()"))
        XCTAssertTrue(app.contains("@Environment(\\.scenePhase)"))
        XCTAssertTrue(app.contains("phase == .active"))
        XCTAssertTrue(app.contains("model.refresh()"))
    }

    func testActivityContractAndManagerUseScheduledStart() throws {
        let attributes = try source(at: "Shared/PinnedEventActivityAttributes.swift")
        let manager = try source(at: "Koyomi/PinnedLiveActivityManager.swift")

        XCTAssertTrue(attributes.contains("ActivityAttributes"))
        XCTAssertTrue(manager.contains("start: plan.activationDate"))
        XCTAssertTrue(manager.contains("staleDate: event.startDate"))
        XCTAssertTrue(manager.contains("sound: .named(\"KoyomiLiveActivitySilent.caf\")"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent("Resources/KoyomiLiveActivitySilent.caf")
                    .path
            )
        )
    }

    func testPrivacyCopyDisclosesCompanionDeviceMirroringWithoutClaimingServerUpload() throws {
        let permissionView = try source(at: "Koyomi/CalendarPermissionView.swift")
        let readme = try source(at: "README.md")
        let project = try source(at: "project.yml")

        for source in [permissionView, readme, project] {
            XCTAssertTrue(source.contains("外部サーバー"))
            XCTAssertTrue(source.contains("ペアリング済み"))
        }
        XCTAssertTrue(permissionView.contains("Apple WatchやMac"))
        XCTAssertTrue(readme.contains("転送は開発者側では停止できず"))
    }

    func testLiveActivityMarksEventAndTimeDetailsAsPrivate() throws {
        let widget = try source(at: "KoyomiWidget/KoyomiPinnedEventLiveActivity.swift")

        XCTAssertGreaterThanOrEqual(
            widget.components(separatedBy: ".privacySensitive()").count - 1,
            6
        )
    }

    func testLiveActivityCountdownStopsAtEventStart() throws {
        let widget = try source(at: "KoyomiWidget/KoyomiPinnedEventLiveActivity.swift")

        XCTAssertTrue(widget.contains("pauseTime: startDate"))
        XCTAssertTrue(widget.contains("timerInterval:"))
        XCTAssertTrue(widget.contains("DynamicIsland"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
