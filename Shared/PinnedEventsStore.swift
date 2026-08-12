import Foundation
import Security

public protocol PinnedEventsDataStorage: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

public enum PinnedEventsStoreError: Error, Equatable, Sendable {
    case invalidData
}

public final class UserDefaultsPinnedEventsDataStorage: PinnedEventsDataStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = KoyomiSharedStorage.pinnedEventSnapshotsKey) {
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
        account: String = KoyomiSharedStorage.pinnedEventSnapshotsKey
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

/// Replacement-only cache for Widget display snapshots.
/// Calendar event titles remain the authority for whether an event is pinned.
public final class PinnedEventsStore: @unchecked Sendable {
    private let storage: any PinnedEventsDataStorage
    private let migrationStorage: (any PinnedEventsDataStorage)?
    private let lock = NSLock()

    public convenience init(defaults: UserDefaults, key: String = KoyomiSharedStorage.pinnedEventSnapshotsKey) {
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

    /// Loads legacy migration state only after its primary/fallback copies are
    /// durably synchronized. Any read, decode, or synchronization error fails
    /// closed so Calendar is never mutated from uncertain local state.
    public func loadMigrationState() throws -> [PinnedEvent] {
        lock.lock()
        defer { lock.unlock() }

        if let primaryData = try storage.read() {
            guard let events = decode(primaryData) else {
                throw PinnedEventsStoreError.invalidData
            }
            if let migrationStorage {
                try migrationStorage.write(encode(events))
            }
            return events
        }

        guard let migrationStorage else { return [] }
        guard let migrationData = try migrationStorage.read() else { return [] }
        guard let events = decode(migrationData) else {
            throw PinnedEventsStoreError.invalidData
        }
        try storage.write(encode(events))
        return events
    }

    public func save(_ events: [PinnedEvent]) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeUnlocked(normalize(events))
    }

    /// Keeps every legacy copy in the same migration state so stale fallback
    /// data cannot survive behind the primary store and reappear later.
    public func saveMigrationState(_ events: [PinnedEvent]) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try encode(normalize(events))
        guard let migrationStorage else {
            try storage.write(data)
            return
        }

        let previousPrimaryData = try storage.read()
        let previousMigrationData = try migrationStorage.read()
        try migrationStorage.write(data)
        do {
            try storage.write(data)
        } catch {
            // The old primary remains authoritative. Restore the fallback now;
            // if the process dies first, the next load mirrors the old primary.
            let rollbackData: Data
            if let previousPrimaryData {
                rollbackData = previousPrimaryData
            } else if let previousMigrationData {
                rollbackData = previousMigrationData
            } else {
                rollbackData = try encode([])
            }
            try? migrationStorage.write(rollbackData)
            throw error
        }
    }

    private func readUnlocked() -> [PinnedEvent] {
        let primaryData: Data?
        do {
            primaryData = try storage.read()
        } catch {
            return []
        }

        if let primaryData {
            guard let events = decode(primaryData) else {
                // Corrupt primary data must not destroy a healthy migration fallback.
                return []
            }
            // Primary wins, but mirror it so a stale fallback cannot reappear
            // after a later Keychain restore or reset.
            if let migrationStorage, let synchronizedData = try? encode(events) {
                try? migrationStorage.write(synchronizedData)
            }
            return events
        }

        guard
            let migrationStorage,
            let legacyData = try? migrationStorage.read(),
            let events = decode(legacyData)
        else {
            return []
        }

        do {
            try writeUnlocked(events)
            return events
        } catch {
            return []
        }
    }

    private func writeUnlocked(_ events: [PinnedEvent]) throws {
        try storage.write(encode(events))
    }

    private func encode(_ events: [PinnedEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(events)
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
