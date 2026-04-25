import Foundation

public enum WriteBackupRecordStorageError: Error, Sendable, LocalizedError {
    case missing_location(
        id: UUID,
        target: URL
    )

    public var errorDescription: String? {
        switch self {
        case .missing_location(let id, let target):
            return "Backup record \(id.uuidString.lowercased()) has no local location for: \(target.path)"
        }
    }
}

public struct WriteBackupRecordStorageAPI: Sendable {
    public let record: WriteBackupRecord

    public init(
        record: WriteBackupRecord
    ) {
        self.record = record
    }

    public var localURL: URL? {
        record.storage?.localURL
    }

    public var isLocal: Bool {
        localURL != nil
    }

    public func requireLocalURL() throws -> URL {
        guard let localURL else {
            throw WriteBackupRecordStorageError.missing_location(
                id: record.id,
                target: record.target
            )
        }

        return localURL
    }
}

public extension WriteBackupRecord {
    var stored: WriteBackupRecordStorageAPI {
        .init(
            record: self
        )
    }
}

public protocol WriteBackupRecordStore: Sendable {
    @discardableResult
    func store(
        _ request: WriteBackupRequest
    ) throws -> WriteBackupRecord

    func load(
        _ record: WriteBackupRecord
    ) throws -> Data?

    func delete(
        _ record: WriteBackupRecord
    ) throws
}

public extension WriteBackupRecordStore {
    func deleteLocal(
        _ record: WriteBackupRecord
    ) throws {
        let url = try record.stored.requireLocalURL()

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return
        }

        try FileManager.default.removeItem(
            at: url
        )
    }
}
