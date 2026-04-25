import Foundation

public enum WriteMutationBackupRollbackError: Error, Sendable, LocalizedError {
    case target_mismatch(
        recordTarget: URL,
        writerTarget: URL
    )

    case missing_backup_record(
        id: UUID,
        target: URL
    )

    case guard_failed(
        target: URL,
        expected: StandardContentFingerprint,
        actual: StandardContentFingerprint
    )

    public var errorDescription: String? {
        switch self {
        case .target_mismatch(let recordTarget, let writerTarget):
            return "Rollback target mismatch. Record target: \(recordTarget.path). Writer target: \(writerTarget.path)."

        case .missing_backup_record(let id, let target):
            return "Rollback mutation \(id.uuidString.lowercased()) has no backup record for \(target.path)."

        case .guard_failed(let target, let expected, let actual):
            return "Backup rollback blocked for \(target.path). Expected current fingerprint \(expected), but found \(actual)."
        }
    }
}

public struct WriteMutationBackupRollbackResult: Sendable {
    public let sourceRecord: WriteMutationRecord
    public let backupRecord: WriteBackupRecord
    public let writeResult: SafeWriteResult
    public let rollbackRecord: WriteMutationRecord

    public init(
        sourceRecord: WriteMutationRecord,
        backupRecord: WriteBackupRecord,
        writeResult: SafeWriteResult,
        rollbackRecord: WriteMutationRecord
    ) {
        self.sourceRecord = sourceRecord
        self.backupRecord = backupRecord
        self.writeResult = writeResult
        self.rollbackRecord = rollbackRecord
    }
}

public extension WriteMutationRecord {
    var hasBackupRollbackPayload: Bool {
        backupRecord != nil
    }

    func canRollbackBackup(
        from currentData: Data
    ) -> Bool {
        guard let expected = rollbackGuard?.requiredCurrentFingerprint else {
            return true
        }

        return StandardContentFingerprint.fingerprint(
            for: currentData
        ) == expected
    }
}

public extension StandardWriter {
    @discardableResult
    func rollbackFromBackup(
        _ record: WriteMutationRecord,
        options: SafeWriteOptions = .overwriteWithoutBackup,
        backupStore: (any WriteBackupStore)? = nil,
        checkTarget: Bool = true
    ) throws -> WriteMutationBackupRollbackResult {
        if checkTarget,
           record.target.standardizedFileURL.path != url.standardizedFileURL.path {
            throw WriteMutationBackupRollbackError.target_mismatch(
                recordTarget: record.target,
                writerTarget: url
            )
        }

        guard let backupRecord = record.backupRecord else {
            throw WriteMutationBackupRollbackError.missing_backup_record(
                id: record.id,
                target: record.target
            )
        }

        let currentData = try IntegratedReader.data(
            at: url,
            missingFileReturnsEmpty: false
        )

        if let expected = record.rollbackGuard?.requiredCurrentFingerprint {
            let actual = StandardContentFingerprint.fingerprint(
                for: currentData
            )

            guard actual == expected else {
                throw WriteMutationBackupRollbackError.guard_failed(
                    target: url,
                    expected: expected,
                    actual: actual
                )
            }
        }

        let writeResult = try backups.restore(
            backupRecord,
            options: options,
            store: backupStore
        )

        let rollbackRecord = writeResult.mutationRecord(
            operationKind: .rollback,
            metadata: [
                WriteMutationMetadataKey.rollback_of: record.id.uuidString.lowercased(),
                WriteMutationMetadataKey.rollback_strategy: WriteMutationRollbackStrategy.backup_record.rawValue,
                WriteMutationMetadataKey.resource_change: WriteResourceChangeKind.update.rawValue,
                WriteMutationMetadataKey.delta_kind: WriteDeltaKind.replacement.rawValue,
            ]
        )

        return .init(
            sourceRecord: record,
            backupRecord: backupRecord,
            writeResult: writeResult,
            rollbackRecord: rollbackRecord
        )
    }
}

public extension WriteRollbackAPI {
    @discardableResult
    func backup(
        _ record: WriteMutationRecord,
        options: SafeWriteOptions = .overwriteWithoutBackup,
        backupStore: (any WriteBackupStore)? = nil,
        checkTarget: Bool = true
    ) throws -> WriteMutationBackupRollbackResult {
        try writer.rollbackFromBackup(
            record,
            options: options,
            backupStore: backupStore,
            checkTarget: checkTarget
        )
    }
}
