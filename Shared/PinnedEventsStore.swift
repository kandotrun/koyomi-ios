import Foundation
import Security

public protocol PinnedEventsDataStorage: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

public final class UserDefaultsPinnedEventsDataStorage: PinnedEventsDataStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = KoyomiSharedStorage.pinnedEventsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func read() throws -> Data? {
        defaults.data(forKey: key)
    }

    public func write(_ data: Data) throws {
        defaults.set(data, forKey: key)
    }
}

public struct KeychainPinnedEventsStorageError: Error, Equatable, Sendable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }
}

public final class KeychainPinnedEventsDataStorage: PinnedEventsDataStorage, @unchecked Sendable {
    private let accessGroup: String
    private let service: String
    private let account: String

    public init(
        accessGroup: String = KoyomiSharedStorage.keychainAccessGroup,
        service: String = KoyomiSharedStorage.keychainService,
        account: String = KoyomiSharedStorage.pinnedEventsKey
    ) {
        self.accessGroup = accessGroup
        self.service = service
        self.account = account
    }

    public func read() throws -> Data? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainPinnedEventsStorageError(status: status)
        }
    }

    public func write(_ data: Data) throws {
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainPinnedEventsStorageError(status: updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainPinnedEventsStorageError(status: addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

public final class PinnedEventsStore: @unchecked Sendable {
    private let storage: any PinnedEventsDataStorage
    private let migrationStorage: (any PinnedEventsDataStorage)?
    private let lock = NSLock()

    public convenience init(defaults: UserDefaults, key: String = KoyomiSharedStorage.pinnedEventsKey) {
        self.init(storage: UserDefaultsPinnedEventsDataStorage(defaults: defaults, key: key))
    }

    public init(
        storage: any PinnedEventsDataStorage,
        migrationStorage: (any PinnedEventsDataStorage)? = nil
    ) {
        self.storage = storage
        self.migrationStorage = migrationStorage
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
        let primaryData: Data?
        do {
            primaryData = try storage.read()
        } catch {
            return []
        }

        if let primaryData {
            return decode(primaryData) ?? []
        }

        guard
            let migrationStorage,
            let legacyData = try? migrationStorage.read(),
            let events = decode(legacyData)
        else {
            return []
        }

        try? writeUnlocked(events)
        return events
    }

    private func writeUnlocked(_ events: [PinnedEvent]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try storage.write(encoder.encode(events))
    }

    private func decode(_ data: Data) -> [PinnedEvent]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let decoded = try? decoder.decode([PinnedEvent].self, from: data) else { return nil }
        return normalize(decoded)
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
