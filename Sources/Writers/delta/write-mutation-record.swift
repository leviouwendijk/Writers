import Foundation

public enum WriteMutationOperationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case write_data
    case write_text
    case append_text
    case edit_operations
    case merge_edit
    case rollback
    case unknown
}

public struct WriteMutationDifferenceSummary: Codable, Sendable, Hashable {
    public let insertions: Int
    public let deletions: Int
    public let changeCount: Int
    public let hasChanges: Bool

    public init(
        insertions: Int,
        deletions: Int,
        changeCount: Int,
        hasChanges: Bool
    ) {
        self.insertions = insertions
        self.deletions = deletions
        self.changeCount = changeCount
        self.hasChanges = hasChanges
    }

    public init(
        _ difference: SafeFileDifference
    ) {
        self.init(
            insertions: difference.insertions,
            deletions: difference.deletions,
            changeCount: difference.changeCount,
            hasChanges: difference.hasChanges
        )
    }
}

public struct WriteRollbackGuard: Codable, Sendable, Hashable {
    public let requiredCurrentFingerprint: StandardContentFingerprint?
    public let reason: String

    public init(
        requiredCurrentFingerprint: StandardContentFingerprint?,
        reason: String
    ) {
        self.requiredCurrentFingerprint = requiredCurrentFingerprint
        self.reason = reason
    }
}

public struct WriteMutationRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let target: URL
    public let createdAt: Date
    public let operationKind: WriteMutationOperationKind
    public let before: WriteMutationSnapshot?
    public let after: WriteMutationSnapshot?
    public let difference: WriteMutationDifferenceSummary?
    public let backupRecord: WriteBackupRecord?
    public let writeResult: WriteResult?
    public let rollbackOperations: [StandardEditOperation]
    public let rollbackGuard: WriteRollbackGuard?
    public let metadata: [String: String]

    public init(
        id: UUID = .init(),
        target: URL,
        createdAt: Date = .init(),
        operationKind: WriteMutationOperationKind,
        before: WriteMutationSnapshot? = nil,
        after: WriteMutationSnapshot? = nil,
        difference: WriteMutationDifferenceSummary? = nil,
        backupRecord: WriteBackupRecord? = nil,
        writeResult: WriteResult? = nil,
        rollbackOperations: [StandardEditOperation] = [],
        rollbackGuard: WriteRollbackGuard? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.target = target
        self.createdAt = createdAt
        self.operationKind = operationKind
        self.before = before
        self.after = after
        self.difference = difference
        self.backupRecord = backupRecord
        self.writeResult = writeResult
        self.rollbackOperations = rollbackOperations
        self.rollbackGuard = rollbackGuard
        self.metadata = metadata
    }
}

public extension WriteResult {
    func mutationRecord(
        operationKind: WriteMutationOperationKind = .unknown,
        difference: WriteMutationDifferenceSummary? = nil,
        metadata: [String: String] = [:]
    ) -> WriteMutationRecord {
        .init(
            target: target,
            operationKind: operationKind,
            before: beforeSnapshot,
            after: afterSnapshot,
            difference: difference,
            backupRecord: backupRecord,
            writeResult: self,
            rollbackGuard: afterSnapshot.map {
                .init(
                    requiredCurrentFingerprint: $0.fingerprint,
                    reason: "Current content must still match the post-write snapshot before automatic rollback."
                )
            },
            metadata: metadata
        )
    }
}

public extension StandardEditResult {
    func mutationRecord(
        id: UUID = .init(),
        createdAt: Date = .init(),
        operationKind: WriteMutationOperationKind = .edit_operations,
        storeContent: Bool = true,
        metadata: [String: String] = [:]
    ) -> WriteMutationRecord {
        .init(
            id: id,
            target: target,
            createdAt: createdAt,
            operationKind: operationKind,
            before: .init(
                content: originalContent,
                storeContent: storeContent
            ),
            after: .init(
                content: editedContent,
                storeContent: storeContent
            ),
            difference: .init(
                difference
            ),
            backupRecord: writeResult?.backupRecord,
            writeResult: writeResult,
            rollbackOperations: rollbackOperations,
            rollbackGuard: .init(
                requiredCurrentFingerprint: editedFingerprint,
                reason: "Current content must still match the edited snapshot before automatic rollback."
            ),
            metadata: metadata
        )
    }
}

public extension StandardEditRecord {
    func mutationRecord(
        id: UUID? = nil,
        operationKind: WriteMutationOperationKind = .edit_operations,
        storeContent: Bool = true,
        metadata: [String: String] = [:]
    ) -> WriteMutationRecord {
        .init(
            id: id ?? self.id,
            target: target,
            createdAt: createdAt,
            operationKind: operationKind,
            before: .init(
                content: base.content,
                storeContent: storeContent
            ),
            after: .init(
                content: edited.content,
                storeContent: storeContent
            ),
            difference: nil,
            backupRecord: nil,
            writeResult: nil,
            rollbackOperations: rollbackOperations,
            rollbackGuard: .init(
                requiredCurrentFingerprint: editedFingerprint,
                reason: "Current content must still match the edited snapshot before automatic rollback."
            ),
            metadata: metadata
        )
    }
}
