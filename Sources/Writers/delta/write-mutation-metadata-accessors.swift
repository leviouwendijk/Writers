import Foundation

public extension WriteMutationRecord {
    var rollbackSourceID: UUID? {
        typedMetadata.rollbackOf
    }

    var rollbackStrategy: WriteMutationRollbackStrategy? {
        typedMetadata.rollbackStrategy
    }

    var storedResourceChangeKind: WriteResourceChangeKind? {
        typedMetadata.resource
    }

    var storedDeltaKind: WriteDeltaKind? {
        typedMetadata.delta
    }

    var surfacedResourceChangeKind: WriteResourceChangeKind {
        typedMetadata.resource ?? resourceChangeKind
    }

    var surfacedDeltaKind: WriteDeltaKind {
        typedMetadata.delta ?? deltaKind
    }
}
