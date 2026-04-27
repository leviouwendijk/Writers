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
            uuid(
                WriteMutationMetadataKey.rollback_of
            )
        }
        set {
            setUUID(
                newValue,
                for: WriteMutationMetadataKey.rollback_of
            )
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

    public var passID: UUID? {
        get {
            uuid(
                WriteMutationMetadataKey.pass_id
            )
        }
        set {
            setUUID(
                newValue,
                for: WriteMutationMetadataKey.pass_id
            )
        }
    }

    public var passIndex: Int? {
        get {
            int(
                WriteMutationMetadataKey.pass_index
            )
        }
        set {
            setInt(
                newValue,
                for: WriteMutationMetadataKey.pass_index
            )
        }
    }

    public var passCount: Int? {
        get {
            int(
                WriteMutationMetadataKey.pass_count
            )
        }
        set {
            setInt(
                newValue,
                for: WriteMutationMetadataKey.pass_count
            )
        }
    }

    public var rollbackOfPass: UUID? {
        get {
            uuid(
                WriteMutationMetadataKey.rollback_of_pass
            )
        }
        set {
            setUUID(
                newValue,
                for: WriteMutationMetadataKey.rollback_of_pass
            )
        }
    }

    public var rollbackPassID: UUID? {
        get {
            uuid(
                WriteMutationMetadataKey.rollback_pass_id
            )
        }
        set {
            setUUID(
                newValue,
                for: WriteMutationMetadataKey.rollback_pass_id
            )
        }
    }

    public var rollbackIndex: Int? {
        get {
            int(
                WriteMutationMetadataKey.rollback_index
            )
        }
        set {
            setInt(
                newValue,
                for: WriteMutationMetadataKey.rollback_index
            )
        }
    }

    public var rollbackCount: Int? {
        get {
            int(
                WriteMutationMetadataKey.rollback_count
            )
        }
        set {
            setInt(
                newValue,
                for: WriteMutationMetadataKey.rollback_count
            )
        }
    }

    public var rollbackAction: StandardMutationRollbackActionKind? {
        get {
            guard let rawValue = raw[
                WriteMutationMetadataKey.rollback_action
            ] else {
                return nil
            }

            return StandardMutationRollbackActionKind(
                rawValue: rawValue
            )
        }
        set {
            raw[
                WriteMutationMetadataKey.rollback_action
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

    private func uuid(
        _ key: String
    ) -> UUID? {
        guard let rawValue = raw[
            key
        ] else {
            return nil
        }

        return UUID(
            uuidString: rawValue
        )
    }

    private mutating func setUUID(
        _ value: UUID?,
        for key: String
    ) {
        raw[
            key
        ] = value?.uuidString.lowercased()
    }

    private func int(
        _ key: String
    ) -> Int? {
        guard let rawValue = raw[
            key
        ] else {
            return nil
        }

        return Int(
            rawValue
        )
    }

    private mutating func setInt(
        _ value: Int?,
        for key: String
    ) {
        raw[
            key
        ] = value.map {
            String(
                $0
            )
        }
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
