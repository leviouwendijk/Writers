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

    var mutationPassID: UUID? {
        typedMetadata.passID
    }

    var mutationPassIndex: Int? {
        typedMetadata.passIndex
    }

    var mutationPassCount: Int? {
        typedMetadata.passCount
    }

    var rollbackOfPassID: UUID? {
        typedMetadata.rollbackOfPass
    }

    var rollbackPassID: UUID? {
        typedMetadata.rollbackPassID
    }

    var rollbackIndex: Int? {
        typedMetadata.rollbackIndex
    }

    var rollbackCount: Int? {
        typedMetadata.rollbackCount
    }

    var mutationRollbackAction: StandardMutationRollbackActionKind? {
        typedMetadata.rollbackAction
    }
}
