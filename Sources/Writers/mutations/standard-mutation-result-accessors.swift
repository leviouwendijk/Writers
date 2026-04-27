import Foundation

public extension StandardMutationResult {
    var forwardRecords: [WriteMutationRecord] {
        records
    }

    var forwardApplied: [UUID] {
        applied
    }

    var rollbackRecords: [WriteMutationRecord] {
        automaticRollback?.records ?? []
    }

    var allRecords: [WriteMutationRecord] {
        forwardRecords + rollbackRecords
    }

    var rolledBack: Bool {
        status == .rolled_back
    }

    var partiallyApplied: Bool {
        status == .partial
    }

    var failedBeforeApplying: Bool {
        status == .failed
    }
}

public extension StandardMutationRollbackResult {
    var allRecords: [WriteMutationRecord] {
        records
    }
}
