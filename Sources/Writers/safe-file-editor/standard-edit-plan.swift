public struct StandardEditPlan: Sendable, Hashable {
    public let operations: [StandardEditOperation]
    public let mode: StandardEditMode
    public let constraint: StandardEditConstraint

    public init(
        operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        constraint: StandardEditConstraint
    ) throws {
        try constraint.validate(
            operations
        )

        self.operations = operations
        self.mode = mode
        self.constraint = constraint
    }

    public init(
        operation: StandardEditOperation,
        mode: StandardEditMode = .sequential,
        constraint: StandardEditConstraint
    ) throws {
        try self.init(
            operations: [
                operation,
            ],
            mode: mode,
            constraint: constraint
        )
    }
}
