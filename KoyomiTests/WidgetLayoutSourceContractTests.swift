import Foundation
import XCTest

final class WidgetLayoutSourceContractTests: XCTestCase {
    func testMediumAndLargeListsFillAvailableHeightFromTopLeading() throws {
        let source = try widgetSource()

        XCTAssertTrue(
            source.contains("mediumContent\n                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"),
            "Medium Widgetは余剰高さがある場合も一覧を上詰めにする"
        )
        XCTAssertTrue(
            source.contains("largeContent\n                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"),
            "Large Widgetは余剰高さがある場合も一覧を上詰めにする"
        )
        XCTAssertFalse(
            source.contains("accessoryContent\n                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"),
            "ロック画面向けWidgetの中央配置は維持する"
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
