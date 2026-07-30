import Foundation

nonisolated struct FileSystemCacheScope: Hashable {
    let appDeviceID: UUID
    let identity: MTPDeviceIdentity
}

nonisolated struct FileSystemCacheKey: Hashable {
    let scope: FileSystemCacheScope
    let storageID: MTPStorageID
    let parentID: MTPObjectID
}

nonisolated struct FileSystemCacheStore {
    private struct Entry {
        let items: [FileItem]
        let timestamp: Date
    }

    private var entries: [FileSystemCacheKey: Entry] = [:]
    private var generationByScope: [FileSystemCacheScope: UInt64] = [:]

    func cachedItems(
        for key: FileSystemCacheKey,
        at date: Date,
        ttl: TimeInterval
    ) -> [FileItem]? {
        guard let entry = entries[key],
              date.timeIntervalSince(entry.timestamp) <= ttl else {
            return nil
        }
        return entry.items
    }

    mutating func generation(for scope: FileSystemCacheScope) -> UInt64 {
        if generationByScope[scope] == nil {
            generationByScope[scope] = 0
        }
        return generationByScope[scope, default: 0]
    }

    mutating func store(
        _ items: [FileItem],
        for key: FileSystemCacheKey,
        timestamp: Date,
        expectedGeneration: UInt64
    ) -> Bool {
        guard generationByScope[key.scope, default: 0] == expectedGeneration else {
            return false
        }
        entries[key] = Entry(items: items, timestamp: timestamp)
        return true
    }

    mutating func invalidateAll() {
        entries.removeAll()
        for scope in Array(generationByScope.keys) {
            generationByScope[scope, default: 0] &+= 1
        }
    }

    mutating func invalidate(_ scope: FileSystemCacheScope) {
        entries = entries.filter { $0.key.scope != scope }
        generationByScope[scope, default: 0] &+= 1
    }
}
