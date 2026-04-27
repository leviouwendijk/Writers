public struct WorkspaceMutationAPI: Sendable {
    public let workspace: WorkspaceWriter

    public init(
        workspace: WorkspaceWriter
    ) {
        self.workspace = workspace
    }

    public func standardEntries(
        _ entries: [WorkspaceMutationEntry]
    ) throws -> [StandardMutationEntry] {
        try entries.map {
            try $0.standardEntry(
                in: workspace
            )
        }
    }

    public func standardEntry(
        _ entry: WorkspaceMutationEntry
    ) throws -> StandardMutationEntry {
        try entry.standardEntry(
            in: workspace
        )
    }

    public func plan(
        _ entries: [WorkspaceMutationEntry],
        metadata: [String: String] = [:]
    ) throws -> StandardMutationPlan {
        try workspace.writer.mutations.plan(
            standardEntries(
                entries
            ),
            metadata: metadata
        )
    }

    public func plan(
        _ entry: WorkspaceMutationEntry,
        metadata: [String: String] = [:]
    ) throws -> StandardMutationPlan {
        try plan(
            [
                entry,
            ],
            metadata: metadata
        )
    }

    @discardableResult
    public func apply(
        _ plan: StandardMutationPlan,
        options: StandardMutationApplyOptions = .init()
    ) -> StandardMutationResult {
        workspace.writer.mutations.apply(
            plan,
            options: options
        )
    }

    @discardableResult
    public func rollback(
        _ plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions = .init()
    ) -> StandardMutationRollbackResult {
        workspace.writer.rollbacks.apply(
            plan,
            options: options
        )
    }
}
