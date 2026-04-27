public struct StandardMutationAPI: Sendable {
    public init() {}

    public func plan(
        _ entries: [StandardMutationEntry],
        metadata: [String: String] = [:]
    ) throws -> StandardMutationPlan {
        try StandardMutationPlanner().plan(
            entries,
            metadata: metadata
        )
    }

    public func plan(
        _ entry: StandardMutationEntry,
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
        StandardMutationApplier().apply(
            plan,
            options: options
        )
    }
}

public extension FileWriter {
    var mutations: StandardMutationAPI {
        .init()
    }
}
