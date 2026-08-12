import Foundation
import XCTest

final class WidgetLayoutSourceContractTests: XCTestCase {
    func testMediumAndLargeListsFillAvailableHeightFromTopLeading() throws {
        let source = try widgetSource()
        let normalizedSource = source
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        XCTAssertTrue(
            normalizedSource.contains("case .systemMedium: mediumContent .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"),
            "Medium Widgetは余剰高さがある場合も一覧を上詰めにする"
        )
        XCTAssertTrue(
            normalizedSource.contains("case .systemLarge: largeContent .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"),
            "Large Widgetは余剰高さがある場合も一覧を上詰めにする"
        )
        XCTAssertFalse(
            normalizedSource.contains("case .accessoryRectangular: accessoryContent .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"),
            "ロック画面向けWidgetの中央配置は維持する"
        )
    }

    func testEveryCountdownWidgetFamilyRendersDeadlineProximity() throws {
        let source = try widgetSource()

        XCTAssertEqual(
            source.components(separatedBy: "proximityIndicator(for: pin").count - 1,
            3,
            "Small、Medium/Large共通一覧、ロック画面と共通描画ヘルパーで期限メーターを表示する"
        )
        XCTAssertTrue(
            source.contains("private func proximityIndicator("),
            "Widgetの期限メーターは一箇所に集約する"
        )
    }

    func testDeadlineProximityUsesOneActiveLevelInsteadOfCumulativeProgress() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let meterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Shared", isDirectory: true)
                .appendingPathComponent("CountdownProximityMeter.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            meterSource.contains("index == state.activeSegmentIndex"),
            "期限グラフは累積進捗に見せず、現在の接近レベルだけを点灯する"
        )
        XCTAssertFalse(
            meterSource.contains("index < state."),
            "期限グラフを進捗率に見える累積充填へ戻さない"
        )
        XCTAssertTrue(
            meterSource.contains("HStack(alignment: .bottom"),
            "右へ行くほど高いシグナル形状で、期限が近づく方向を視覚化する"
        )
        XCTAssertTrue(
            meterSource.contains("return 0.32 +"),
            "最小段と最大段の高低差を十分に取り、実寸でも方向を判別できるようにする"
        )
    }

    func testExpandedDeadlineGraphLabelsItsDirectionAndUsesVisibleTracks() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Koyomi", isDirectory: true)
                .appendingPathComponent("PinnedEventsSection.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains("Text(\"余裕\")"))
        XCTAssertTrue(appSource.contains("Text(\"間近\")"))
        XCTAssertEqual(
            appSource.components(separatedBy: "trackColor: Color.primary.opacity(0.50)").count - 1,
            3,
            "折りたたみ・アクセシビリティ・展開表示の全メーターで5段の尺度を判別できるコントラストを保つ"
        )
    }

    private func widgetSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("KoyomiWidget", isDirectory: true)
            .appendingPathComponent("KoyomiWidget.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
