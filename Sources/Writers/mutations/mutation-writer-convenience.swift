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
        options: StandardMutationApplyOptions = .init()
    ) -> StandardMutationResult {
        Self().mutations.apply(
            plan,
            options: options
        )
    }

    @discardableResult
    static func rollback(
        _ plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions = .init()
    ) -> StandardMutationRollbackResult {
        Self().rollbacks.apply(
            plan,
            options: options
        )
    }
}
