import Foundation

public final class PinnedEventsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public convenience init(suiteName: String = KoyomiAppGroup.identifier) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.init(defaults: defaults, key: KoyomiAppGroup.pinnedEventsKey)
    }

    public init(defaults: UserDefaults, key: String = KoyomiAppGroup.pinnedEventsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [PinnedEvent] {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked()
    }

    public func contains(id: String) -> Bool {
        load().contains { $0.id == id }
    }

    public func save(_ events: [PinnedEvent]) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeUnlocked(normalize(events))
    }

    @discardableResult
    public func toggle(_ event: PinnedEvent) throws -> [PinnedEvent] {
        lock.lock()
        defer { lock.unlock() }

        var events = readUnlocked()
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events.remove(at: index)
        } else {
            events.append(event)
        }
        events = normalize(events)
        try writeUnlocked(events)
        return events
    }

    @discardableResult
    public func remove(id: String) throws -> [PinnedEvent] {
        lock.lock()
        defer { lock.unlock() }

        let events = normalize(readUnlocked().filter { $0.id != id })
        try writeUnlocked(events)
        return events
    }

    private func readUnlocked() -> [PinnedEvent] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let decoded = try? decoder.decode([PinnedEvent].self, from: data) else { return [] }
        return normalize(decoded)
    }

    private func writeUnlocked(_ events: [PinnedEvent]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        defaults.set(try encoder.encode(events), forKey: key)
    }

    private func normalize(_ events: [PinnedEvent]) -> [PinnedEvent] {
        var latestByID: [String: PinnedEvent] = [:]
        for event in events {
            latestByID[event.id] = event
        }
        return latestByID.values.sorted {
            if $0.startDate == $1.startDate { return $0.id < $1.id }
            return $0.startDate < $1.startDate
        }
    }
}
