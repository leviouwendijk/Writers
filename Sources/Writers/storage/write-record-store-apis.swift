import Foundation

public struct WriteRecordQuery: Sendable, Codable, Hashable {
    public var target: URL?
    public var latestFirst: Bool
    public var limit: Int?

    public init(
        target: URL? = nil,
        latestFirst: Bool = true,
        limit: Int? = nil
    ) {
        self.target = target
        self.latestFirst = latestFirst
        self.limit = limit
    }

    public static let all = Self()

    public static func target(
        _ target: URL,
        latestFirst: Bool = true,
        limit: Int? = nil
    ) -> Self {
        .init(
            target: target,
            latestFirst: latestFirst,
            limit: limit
        )
    }
}

public enum WriteRecords {
    public struct LocalAPI: Sendable {
        public init() {}

        public func mutations(
            directory: URL
        ) -> StandardMutationRecordStore {
            .init(
                directory: directory
            )
        }

        public func edits(
            directory: URL
        ) -> StandardEditRecordStore {
            .init(
                directoryURL: directory
            )
        }
    }

    public static let local: LocalAPI = .init()
}

public struct WriteMutationRecordStoreAPI: Sendable {
    public let store: any WriteMutationRecordStore

    public init(
        store: any WriteMutationRecordStore
    ) {
        self.store = store
    }

    @discardableResult
    public func save(
        _ record: WriteMutationRecord
    ) throws -> WriteStoredRecord {
        try store.store(
            record
        )
    }

    public func load(
        _ stored: WriteStoredRecord
    ) throws -> WriteMutationRecord? {
        try store.load(
            stored
        )
    }

    public func load(
        _ id: UUID
    ) throws -> WriteMutationRecord? {
        try store.load(
            id
        )
    }

    public func stored(
        _ id: UUID
    ) throws -> WriteStoredRecord? {
        try store.stored(
            id
        )
    }

    public func list(
        _ query: WriteRecordQuery = .all
    ) throws -> [WriteStoredRecord] {
        try store.list(
            query
        )
    }

    public func delete(
        _ stored: WriteStoredRecord
    ) throws {
        try store.delete(
            stored
        )
    }

    public func delete(
        _ id: UUID
    ) throws {
        try store.delete(
            id
        )
    }
}

public struct WriteEditRecordStoreAPI: Sendable {
    public let store: any WriteEditRecordStore

    public init(
        store: any WriteEditRecordStore
    ) {
        self.store = store
    }

    @discardableResult
    public func save(
        _ record: StandardEditRecord
    ) throws -> WriteStoredRecord {
        try store.store(
            record
        )
    }

    public func load(
        _ stored: WriteStoredRecord
    ) throws -> StandardEditRecord? {
        try store.load(
            stored
        )
    }

    public func load(
        _ id: UUID
    ) throws -> StandardEditRecord? {
        try store.load(
            id
        )
    }

    public func stored(
        _ id: UUID
    ) throws -> WriteStoredRecord? {
        try store.stored(
            id
        )
    }

    public func list(
        _ query: WriteRecordQuery = .all
    ) throws -> [WriteStoredRecord] {
        try store.list(
            query
        )
    }

    public func delete(
        _ stored: WriteStoredRecord
    ) throws {
        try store.delete(
            stored
        )
    }

    public func delete(
        _ id: UUID
    ) throws {
        try store.delete(
            id
        )
    }
}

public extension WriteMutationRecordStore {
    var records: WriteMutationRecordStoreAPI {
        .init(
            store: self
        )
    }
}

public extension WriteEditRecordStore {
    var records: WriteEditRecordStoreAPI {
        .init(
            store: self
        )
    }
}
