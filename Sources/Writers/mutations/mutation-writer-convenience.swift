public extension MutationWriter {
    static func plan(
        _ entries: [StandardMutationEntry],
        metadata: [String: String] = [:]
    ) throws -> StandardMutationPlan {
        try Self().mutations.plan(
            entries,
            metadata: metadata
        )
    }

    static func plan(
        _ entry: StandardMutationEntry,
        metadata: [String: String] = [:]
    ) throws -> StandardMutationPlan {
        try Self().mutations.plan(
            entry,
            metadata: metadata
        )
    }

    @discardableResult
    static func apply(
        _ plan: StandardMutationPlan,
        options: StandardMutationApplyOptions = .init(),
        context: WriteExecutionContext = .init()
    ) -> StandardMutationResult {
        Self().mutations.apply(
            plan,
            options: options,
            context: context
        )
    }

    @discardableResult
    static func rollback(
        _ plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions = .init(),
        context: WriteExecutionContext = .init()
    ) -> StandardMutationRollbackResult {
        Self().rollbacks.apply(
            plan,
            options: options,
            context: context
        )
    }
}
