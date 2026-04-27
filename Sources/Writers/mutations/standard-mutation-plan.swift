import Foundation

public struct StandardMutationPlan: Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let entries: [StandardPlannedMutation]
    public let metadata: [String: String]
    public let report: StandardMutationReport

    public init(
        id: UUID = .init(),
        createdAt: Date = .init(),
        entries: [StandardPlannedMutation],
        metadata: [String: String] = [:]
    ) throws {
        guard !entries.isEmpty else {
            throw StandardMutationError.empty_entries
        }

        self.id = id
        self.createdAt = createdAt
        self.entries = entries
        self.metadata = metadata
        self.report = .init(
            id: id,
            entries: entries
        )
    }

    public var rollback: StandardMutationRollbackPlan {
        .init(
            source: id,
            actions: entries
                .reversed()
                .map(\.rollback)
        )
    }
}

public struct StandardPlannedMutation: Sendable, Identifiable {
    public let id: UUID
    public let index: Int
    public let entry: StandardMutationEntry
    public let target: URL
    public let before: StandardResourceState
    public let after: StandardResourceState
    public let diff: WriteMutationDifferenceSummary?
    public let resource: WriteResourceChangeKind
    public let delta: WriteDeltaKind
    public let writePlan: WritePlan?
    public let editPlan: StandardEditPlan?
    public let editBatch: StandardEditBatchPlan?
    public let rollback: StandardMutationRollbackAction
    public let warnings: [StandardMutationWarning]

    public init(
        id: UUID = .init(),
        index: Int,
        entry: StandardMutationEntry,
        target: URL,
        before: StandardResourceState,
        after: StandardResourceState,
        diff: WriteMutationDifferenceSummary?,
        resource: WriteResourceChangeKind,
        delta: WriteDeltaKind,
        writePlan: WritePlan? = nil,
        editPlan: StandardEditPlan? = nil,
        editBatch: StandardEditBatchPlan? = nil,
        rollback: StandardMutationRollbackAction,
        warnings: [StandardMutationWarning] = []
    ) {
        self.id = id
        self.index = index
        self.entry = entry
        self.target = target.standardizedFileURL
        self.before = before
        self.after = after
        self.diff = diff
        self.resource = resource
        self.delta = delta
        self.writePlan = writePlan
        self.editPlan = editPlan
        self.editBatch = editBatch
        self.rollback = rollback
        self.warnings = warnings
    }

    public var report: StandardPlannedMutationReport {
        .init(
            id: id,
            index: index,
            target: target,
            resource: resource,
            delta: delta,
            warningCodes: warnings
        )
    }
}
