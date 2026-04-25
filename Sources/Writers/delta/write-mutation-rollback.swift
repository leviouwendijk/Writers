import Foundation

public enum WriteMutationRollbackError: Error, LocalizedError, Sendable {
    case target_mismatch(
        recordTarget: URL,
        writerTarget: URL
    )
    case guard_failed(
        target: URL,
        expected: StandardContentFingerprint,
        actual: StandardContentFingerprint
    )
    case missing_payload(
        id: UUID,
        target: URL
    )

    public var errorDescription: String? {
        switch self {
        case .target_mismatch(let recordTarget, let writerTarget):
            return "Rollback target mismatch. Record target: \(recordTarget.path). Writer target: \(writerTarget.path)."

        case .guard_failed(let target, let expected, let actual):
            return "Rollback blocked for \(target.path). Expected current fingerprint \(expected), but found \(actual)."

        case .missing_payload(let id, let target):
            return "Rollback mutation \(id.uuidString.lowercased()) has no before snapshot content and no rollback operations for \(target.path)."
        }
    }
}

public struct WriteMutationRollbackPreview: Codable, Sendable, Hashable {
    public let recordID: UUID
    public let target: URL
    public let strategy: WriteMutationRollbackStrategy
    public let current: WriteMutationSnapshot
    public let rollback: WriteMutationSnapshot
    public let rollbackContent: String

    public init(
        recordID: UUID,
        target: URL,
        strategy: WriteMutationRollbackStrategy,
        current: WriteMutationSnapshot,
        rollback: WriteMutationSnapshot,
        rollbackContent: String
    ) {
        self.recordID = recordID
        self.target = target
        self.strategy = strategy
        self.current = current
        self.rollback = rollback
        self.rollbackContent = rollbackContent
    }

    public var hasChanges: Bool {
        current.fingerprint != rollback.fingerprint
    }
}

public struct WriteMutationRollbackResult: Sendable {
    public let preview: WriteMutationRollbackPreview
    public let writeResult: SafeWriteResult
    public let rollbackRecord: WriteMutationRecord

    public init(
        preview: WriteMutationRollbackPreview,
        writeResult: SafeWriteResult,
        rollbackRecord: WriteMutationRecord
    ) {
        self.preview = preview
        self.writeResult = writeResult
        self.rollbackRecord = rollbackRecord
    }
}

public extension WriteMutationRecord {
    var hasRollbackPayload: Bool {
        before?.content != nil || !rollbackOperations.isEmpty
    }

    func canRollback(
        from currentContent: String
    ) -> Bool {
        guard let expected = rollbackGuard?.requiredCurrentFingerprint else {
            return true
        }

        return StandardContentFingerprint.fingerprint(
            for: currentContent
        ) == expected
    }

    func rollbackPreview(
        currentContent: String
    ) throws -> WriteMutationRollbackPreview {
        let current = WriteMutationSnapshot(
            content: currentContent
        )

        if let expected = rollbackGuard?.requiredCurrentFingerprint,
           current.fingerprint != expected {
            throw WriteMutationRollbackError.guard_failed(
                target: target,
                expected: expected,
                actual: current.fingerprint
            )
        }

        let strategy: WriteMutationRollbackStrategy
        let rollbackContent: String

        if let content = before?.content {
            strategy = .before_snapshot
            rollbackContent = content
        } else if !rollbackOperations.isEmpty {
            strategy = .rollback_operations
            rollbackContent = try StandardEditOperation.applying(
                rollbackOperations,
                to: currentContent
            )
        } else {
            throw WriteMutationRollbackError.missing_payload(
                id: id,
                target: target
            )
        }

        return .init(
            recordID: id,
            target: target,
            strategy: strategy,
            current: current,
            rollback: .init(
                content: rollbackContent
            ),
            rollbackContent: rollbackContent
        )
    }
}

public extension StandardWriter {
    func previewRollback(
        _ record: WriteMutationRecord,
        encoding: String.Encoding = .utf8,
        checkTarget: Bool = true
    ) throws -> WriteMutationRollbackPreview {
        if checkTarget,
           !sameRollbackTarget(
                record.target,
                url
           ) {
            throw WriteMutationRollbackError.target_mismatch(
                recordTarget: record.target,
                writerTarget: url
            )
        }

        let current = try IntegratedReader.text(
            at: url,
            encoding: encoding,
            missingFileReturnsEmpty: false,
            normalizeNewlines: false
        )

        return try record.rollbackPreview(
            currentContent: current
        )
    }

    @discardableResult
    func rollback(
        _ record: WriteMutationRecord,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite,
        checkTarget: Bool = true
    ) throws -> WriteMutationRollbackResult {
        let preview = try previewRollback(
            record,
            encoding: encoding,
            checkTarget: checkTarget
        )

        let writeResult = try write(
            preview.rollbackContent,
            encoding: encoding,
            options: options
        )

        let rollbackRecord = writeResult.mutationRecord(
            operationKind: .rollback,
            metadata: [
                WriteMutationMetadataKey.rollback_of: record.id.uuidString.lowercased(),
                WriteMutationMetadataKey.rollback_strategy: preview.strategy.rawValue,
                WriteMutationMetadataKey.resource_change: WriteResourceChangeKind.update.rawValue,
                WriteMutationMetadataKey.delta_kind: WriteDeltaKind.replacement.rawValue,
            ]
        )

        return .init(
            preview: preview,
            writeResult: writeResult,
            rollbackRecord: rollbackRecord
        )
    }

    private func sameRollbackTarget(
        _ lhs: URL,
        _ rhs: URL
    ) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
