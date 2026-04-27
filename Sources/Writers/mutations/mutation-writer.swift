import Foundation

public struct MutationWriter: Sendable {
    public init() {}

    public var mutations: StandardMutationAPI {
        .init()
    }

    public var rollbacks: MutationRollbackAPI {
        .init()
    }

    public func file(
        _ url: URL
    ) -> FileWriter {
        .init(
            url
        )
    }
}

public struct MutationRollbackAPI: Sendable {
    public init() {}

    @discardableResult
    public func apply(
        _ plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions = .init()
    ) -> StandardMutationRollbackResult {
        StandardMutationRollbackApplier().apply(
            plan,
            options: options
        )
    }
}
