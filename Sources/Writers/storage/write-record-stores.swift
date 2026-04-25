import Foundation

public protocol WriteMutationRecordStore: Sendable {
    @discardableResult
    func store(
        _ record: WriteMutationRecord
    ) throws -> WriteStoredRecord

    func load(
        _ stored: WriteStoredRecord
    ) throws -> WriteMutationRecord?

    func list() throws -> [WriteStoredRecord]
}

public protocol WriteEditRecordStore: Sendable {
    @discardableResult
    func store(
        _ record: StandardEditRecord
    ) throws -> WriteStoredRecord

    func load(
        _ stored: WriteStoredRecord
    ) throws -> StandardEditRecord?

    func list() throws -> [WriteStoredRecord]
}

public extension WriteMutationRecordStore {
    func stored(
        _ id: UUID
    ) throws -> WriteStoredRecord? {
        try list().first {
            $0.id == id
        }
    }

    func load(
        _ id: UUID
    ) throws -> WriteMutationRecord? {
        guard let stored = try stored(
            id
        ) else {
            return nil
        }

        return try load(
            stored
        )
    }

    func list(
        _ query: WriteRecordQuery
    ) throws -> [WriteStoredRecord] {
        filterStoredRecords(
            try list(),
            query: query
        )
    }

    func delete(
        _ stored: WriteStoredRecord
    ) throws {
        let url = try stored.requireLocalURL()

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return
        }

        try FileManager.default.removeItem(
            at: url
        )
    }

    func delete(
        _ id: UUID
    ) throws {
        guard let stored = try stored(
            id
        ) else {
            return
        }

        try delete(
            stored
        )
    }
}

public extension WriteEditRecordStore {
    func stored(
        _ id: UUID
    ) throws -> WriteStoredRecord? {
        try list().first {
            $0.id == id
        }
    }

    func load(
        _ id: UUID
    ) throws -> StandardEditRecord? {
        guard let stored = try stored(
            id
        ) else {
            return nil
        }

        return try load(
            stored
        )
    }

    func list(
        _ query: WriteRecordQuery
    ) throws -> [WriteStoredRecord] {
        filterStoredRecords(
            try list(),
            query: query
        )
    }

    func delete(
        _ stored: WriteStoredRecord
    ) throws {
        let url = try stored.requireLocalURL()

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return
        }

        try FileManager.default.removeItem(
            at: url
        )
    }

    func delete(
        _ id: UUID
    ) throws {
        guard let stored = try stored(
            id
        ) else {
            return
        }

        try delete(
            stored
        )
    }
}

private func filterStoredRecords(
    _ records: [WriteStoredRecord],
    query: WriteRecordQuery
) -> [WriteStoredRecord] {
    var records = records

    if let target = query.target {
        let path = target.standardizedFileURL.path
        records = records.filter {
            $0.target.standardizedFileURL.path == path
        }
    }

    records.sort { lhs, rhs in
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return query.latestFirst
            ? lhs.createdAt > rhs.createdAt
            : lhs.createdAt < rhs.createdAt
    }

    if let limit = query.limit {
        return Array(
            records.prefix(
                max(
                    0,
                    limit
                )
            )
        )
    }

    return records
}
