import Foundation

public enum WidgetPinLayoutCapacity {
    public static let single = 1
    public static let medium = 3
    public static let large = 7

    public static func mediumVisibleLimits(isAccessibilitySize: Bool) -> [Int] {
        isAccessibilitySize ? [medium, 2, 1] : [medium]
    }

    public static func largeVisibleLimits(isAccessibilitySize: Bool) -> [Int] {
        isAccessibilitySize ? [4, 3, 2, 1] : [large, 6, 5]
    }

    public static func hiddenCount(totalPins: Int, visibleLimit: Int) -> Int {
        max(totalPins - max(visibleLimit, 0), 0)
    }

    public static func titleLineLimit(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 3 : 1
    }

    public static func countdownColumnWidth(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? 132 : 86
    }
}
