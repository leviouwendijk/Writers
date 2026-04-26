public extension StandardEditOperation {
    func applyingSequential(
        to content: String
    ) throws -> String {
        try applying(
            to: content
        )
    }

    static func applyingSequential(
        _ operations: [Self],
        to content: String
    ) throws -> String {
        try operations.reduce(
            content
        ) { partial, operation in
            try operation.applyingSequential(
                to: partial
            )
        }
    }
}
