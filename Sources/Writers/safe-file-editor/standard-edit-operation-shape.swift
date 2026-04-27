public extension StandardEditOperation {
    func validateLinePayloadShape(
        operationIndex: Int
    ) throws {
        switch self {
        case .replaceLine(_, let content):
            try Self.requireSingleLine(
                content,
                operationIndex: operationIndex,
                operation: kind,
                field: "content"
            )

        case .replaceLineGuarded(_, let expected, let content):
            try Self.requireSingleLine(
                expected,
                operationIndex: operationIndex,
                operation: kind,
                field: "expected"
            )
            try Self.requireSingleLine(
                content,
                operationIndex: operationIndex,
                operation: kind,
                field: "content"
            )

        case .insertLines(let lines, _):
            try Self.requireSingleLineItems(
                lines,
                operationIndex: operationIndex,
                operation: kind,
                field: "lines"
            )

        case .insertLinesGuarded(let lines, _, _):
            try Self.requireSingleLineItems(
                lines,
                operationIndex: operationIndex,
                operation: kind,
                field: "lines"
            )

        case .replaceLines(_, let lines):
            try Self.requireSingleLineItems(
                lines,
                operationIndex: operationIndex,
                operation: kind,
                field: "lines"
            )

        case .replaceLinesGuarded(_, let expected, let lines):
            try Self.requireSingleLineItems(
                expected,
                operationIndex: operationIndex,
                operation: kind,
                field: "expected"
            )
            try Self.requireSingleLineItems(
                lines,
                operationIndex: operationIndex,
                operation: kind,
                field: "lines"
            )

        case .deleteLines:
            return

        case .deleteLinesGuarded(_, let expected):
            try Self.requireSingleLineItems(
                expected,
                operationIndex: operationIndex,
                operation: kind,
                field: "expected"
            )

        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique:
            return
        }
    }
}

private extension StandardEditOperation {
    static func requireSingleLineItems(
        _ lines: [String],
        operationIndex: Int,
        operation: StandardEditOperationKind,
        field: String
    ) throws {
        for pair in lines.enumerated() {
            try requireSingleLine(
                pair.element,
                operationIndex: operationIndex,
                operation: operation,
                field: field,
                lineIndex: pair.offset + 1
            )
        }
    }

    static func requireSingleLine(
        _ value: String,
        operationIndex: Int,
        operation: StandardEditOperationKind,
        field: String,
        lineIndex: Int? = nil
    ) throws {
        guard value.contains("\n") || value.contains("\r") else {
            return
        }

        throw StandardEditViolation.line_payload_contains_newline(
            operationIndex: operationIndex,
            operation: operation,
            field: field,
            lineIndex: lineIndex
        )
    }
}
