import Foundation

extension StandardEditRecordStore: WriteEditRecordStore {
    @discardableResult
    public func store(
        _ record: StandardEditRecord
    ) throws -> WriteStoredRecord {
        let url = try save(
            record
        )

        return .init(
            id: record.id,
            kind: .edit,
            target: record.target,
            createdAt: record.createdAt,
            storage: .local(url)
        )
    }

    public func load(
        _ stored: WriteStoredRecord
    ) throws -> StandardEditRecord? {
        guard stored.kind == .edit else {
            throw WriteRecordStorageError.kind_mismatch(
                expected: .edit,
                actual: stored.kind,
                id: stored.id
            )
        }

        let location = try stored.requireLocalURL()

        guard FileManager.default.fileExists(
            atPath: location.path
        ) else {
            return nil
        }

        return try load(
            location
        )
    }

    public func list() throws -> [WriteStoredRecord] {
        try listRecordURLs().map { url in
            let record = try load(
                url
            )

            return .init(
                id: record.id,
                kind: .edit,
                target: record.target,
                createdAt: record.createdAt,
                storage: .local(url)
            )
        }
    }
}
