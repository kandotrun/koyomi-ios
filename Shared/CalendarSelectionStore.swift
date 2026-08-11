import Foundation

public struct CalendarDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let sourceName: String
    public let colorHex: String
    public let allowsContentModifications: Bool

    public init(
        id: String,
        title: String,
        sourceName: String,
        colorHex: String,
        allowsContentModifications: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sourceName = sourceName
        self.colorHex = colorHex
        self.allowsContentModifications = allowsContentModifications
    }
}

public final class CalendarSelectionStore: @unchecked Sendable {
    public static let defaultKey = "run.kan.koyomi.selected-calendar-identifiers.v1"

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = CalendarSelectionStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func loadSelection(availableCalendars: [CalendarDescriptor]) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }

        let availableIDs = Set(availableCalendars.map(\.id))
        guard defaults.object(forKey: key) != nil else {
            return availableIDs
        }
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(decoded).intersection(availableIDs)
    }

    public func saveSelection(_ calendarIDs: Set<String>) throws {
        lock.lock()
        defer { lock.unlock() }

        let data = try JSONEncoder().encode(calendarIDs.sorted())
        defaults.set(data, forKey: key)
    }
}
