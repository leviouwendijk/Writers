import Foundation

public struct WriteMutationMetadata: Sendable, Codable, Hashable {
    public var raw: [String: String]

    public init(
        raw: [String: String] = [:]
    ) {
        self.raw = raw
    }

    public var rollbackOf: UUID? {
        get {
            guard let rawValue = raw[
                WriteMutationMetadataKey.rollback_of
            ] else {
                return nil
            }

            return UUID(
                uuidString: rawValue
            )
        }
        set {
            raw[
                WriteMutationMetadataKey.rollback_of
            ] = newValue?.uuidString.lowercased()
        }
    }

    public var rollbackStrategy: WriteMutationRollbackStrategy? {
        get {
            guard let rawValue = raw[
                WriteMutationMetadataKey.rollback_strategy
            ] else {
                return nil
            }

            return WriteMutationRollbackStrategy(
                rawValue: rawValue
            )
        }
        set {
            raw[
                WriteMutationMetadataKey.rollback_strategy
            ] = newValue?.rawValue
        }
    }

    public var resource: WriteResourceChangeKind? {
        get {
            guard let rawValue = raw[
                WriteMutationMetadataKey.resource_change
            ] else {
                return nil
            }

            return WriteResourceChangeKind(
                rawValue: rawValue
            )
        }
        set {
            raw[
                WriteMutationMetadataKey.resource_change
            ] = newValue?.rawValue
        }
    }

    public var delta: WriteDeltaKind? {
        get {
            guard let rawValue = raw[
                WriteMutationMetadataKey.delta_kind
            ] else {
                return nil
            }

            return WriteDeltaKind(
                rawValue: rawValue
            )
        }
        set {
            raw[
                WriteMutationMetadataKey.delta_kind
            ] = newValue?.rawValue
        }
    }

    public func setting(
        _ key: String,
        to value: String?
    ) -> Self {
        var copy = self
        copy.raw[
            key
        ] = value
        return copy
    }
}

public extension WriteMutationRecord {
    var typedMetadata: WriteMutationMetadata {
        .init(
            raw: metadata
        )
    }

    func withMetadata(
        _ metadata: WriteMutationMetadata
    ) -> Self {
        .init(
            id: id,
            target: target,
            createdAt: createdAt,
            operationKind: operationKind,
            before: before,
            after: after,
            difference: difference,
            backupRecord: backupRecord,
            writeResult: writeResult,
            rollbackOperations: rollbackOperations,
            rollbackGuard: rollbackGuard,
            metadata: metadata.raw
        )
    }
}
