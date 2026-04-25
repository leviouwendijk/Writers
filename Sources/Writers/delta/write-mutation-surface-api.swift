import Foundation

public struct WriteMutationSurfaceRollbackAPI: Sendable {
    public let record: WriteMutationRecord

    public init(
        record: WriteMutationRecord
    ) {
        self.record = record
    }

    public var of: UUID? {
        record.typedMetadata.rollbackOf
    }

    public var strategy: WriteMutationRollbackStrategy? {
        record.typedMetadata.rollbackStrategy
    }

    public var textAvailable: Bool {
        record.hasRollbackPayload
    }

    public var backupAvailable: Bool {
        record.hasBackupRollbackPayload
    }

    public var available: Bool {
        textAvailable || backupAvailable
    }

    public var strategies: [WriteMutationRollbackStrategy] {
        var out: [WriteMutationRollbackStrategy] = []

        if record.before?.content != nil {
            out.append(
                .before_snapshot
            )
        }

        if !record.rollbackOperations.isEmpty {
            out.append(
                .rollback_operations
            )
        }

        if record.backupRecord != nil {
            out.append(
                .backup_record
            )
        }

        return out
    }
}

public struct WriteMutationSurfaceAPI: Sendable {
    public let record: WriteMutationRecord

    public init(
        record: WriteMutationRecord
    ) {
        self.record = record
    }

    public var resource: WriteResourceChangeKind {
        record.surfacedResourceChangeKind
    }

    public var delta: WriteDeltaKind {
        record.surfacedDeltaKind
    }

    public var rollback: WriteMutationSurfaceRollbackAPI {
        .init(
            record: record
        )
    }

    public var rollbackable: Bool {
        rollback.available
    }

    public var rollbackOf: UUID? {
        rollback.of
    }

    public var rollbackStrategy: WriteMutationRollbackStrategy? {
        rollback.strategy
    }
}

public extension WriteMutationRecord {
    var surface: WriteMutationSurfaceAPI {
        .init(
            record: self
        )
    }
}
