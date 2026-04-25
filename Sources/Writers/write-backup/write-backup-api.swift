import Foundation

public enum WriteBackupLoadError: Error, Sendable, LocalizedError {
    case missing_payload(
        id: UUID,
        target: URL
    )

    case non_text_payload(
        id: UUID,
        target: URL
    )

    public var errorDescription: String? {
        switch self {
        case .missing_payload(let id, let target):
            return "Backup record \(id.uuidString.lowercased()) has no loadable payload for: \(target.path)"

        case .non_text_payload(let id, let target):
            return "Backup record \(id.uuidString.lowercased()) is not decodable as text for: \(target.path)"
        }
    }
}

public struct WriteBackupAPI: Sendable {
    public let writer: StandardWriter

    public init(
        writer: StandardWriter
    ) {
        self.writer = writer
    }

    public func load(
        _ record: WriteBackupRecord,
        store: (any WriteBackupStore)? = nil
    ) throws -> Data? {
        if let localURL = record.storage?.localURL {
            guard FileManager.default.fileExists(
                atPath: localURL.path
            ) else {
                return nil
            }

            return try Data(
                contentsOf: localURL
            )
        }

        guard let store else {
            return nil
        }

        return try store.loadBackup(
            record
        )
    }

    public func loadRequired(
        _ record: WriteBackupRecord,
        store: (any WriteBackupStore)? = nil
    ) throws -> Data {
        guard let data = try load(
            record,
            store: store
        ) else {
            throw WriteBackupLoadError.missing_payload(
                id: record.id,
                target: record.target
            )
        }

        return data
    }

    public func diff(
        _ record: WriteBackupRecord,
        encoding: String.Encoding = .utf8,
        store: (any WriteBackupStore)? = nil
    ) throws -> SafeFileDifference {
        let backupData = try loadRequired(
            record,
            store: store
        )

        guard let backupText = String(
            data: backupData,
            encoding: encoding
        ) else {
            throw WriteBackupLoadError.non_text_payload(
                id: record.id,
                target: record.target
            )
        }

        let currentText = try IntegratedReader.text(
            at: writer.url,
            encoding: encoding,
            missingFileReturnsEmpty: false,
            normalizeNewlines: false
        )

        return WriteDifference.lines(
            old: backupText,
            new: currentText,
            oldName: "\(writer.url.lastPathComponent) (backup)",
            newName: "\(writer.url.lastPathComponent) (current)"
        )
    }

    @discardableResult
    public func restore(
        _ record: WriteBackupRecord,
        options: SafeWriteOptions = .overwriteWithoutBackup,
        store: (any WriteBackupStore)? = nil
    ) throws -> SafeWriteResult {
        let data = try loadRequired(
            record,
            store: store
        )

        return try writer.write(
            data,
            options: options
        )
    }
}

public extension StandardWriter {
    var backups: WriteBackupAPI {
        .init(
            writer: self
        )
    }
}
