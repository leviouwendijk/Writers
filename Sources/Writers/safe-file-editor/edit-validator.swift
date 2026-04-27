import Position

public extension StandardEditConstraint {
    func validate(
        _ result: StandardEditResult
    ) throws {
        try validate(
            result.operations
        )
        try budget.validate(
            result.report
        )
        try scope.validateOriginalRanges(
            result.originalChangedLineRanges
        )
        try scope.validateEditedRanges(
            result.editedChangedLineRanges
        )
    }

    func validated(
        _ result: StandardEditResult
    ) throws -> StandardEditResult {
        try validate(
            result
        )

        return result
    }

    func validate(
        _ operations: [StandardEditOperation]
    ) throws {
        for pair in operations.enumerated() {
            try validate(
                pair.element,
                operationIndex: pair.offset + 1
            )
        }
    }

    func validate(
        _ operation: StandardEditOperation,
        operationIndex: Int
    ) throws {
        let kind = operation.kind

        try operation.validateLinePayloadShape(
            operationIndex: operationIndex
        )

        guard operations.allows(
            kind
        ) else {
            throw StandardEditViolation.operation_not_allowed(
                operationIndex: operationIndex,
                operation: kind,
                allowed: operations.allowed
            )
        }

        try validateGuards(
            operation,
            operationIndex: operationIndex
        )

        try scope.validate(
            operation: operation,
            operationIndex: operationIndex
        )
    }
}

private extension StandardEditConstraint {
    func validateGuards(
        _ operation: StandardEditOperation,
        operationIndex: Int
    ) throws {
        if guards.unguardable == .deny,
           operation.isUnguardable {
            throw StandardEditViolation.unguardable_operation_denied(
                operationIndex: operationIndex,
                operation: operation.kind
            )
        }

        if guards.existingLines == .required,
           operation.touchesExistingLines,
           !operation.hasExistingLineGuard {
            throw StandardEditViolation.operation_requires_guard(
                operationIndex: operationIndex,
                operation: operation.kind
            )
        }

        if guards.insertions == .required,
           operation.isInsertion,
           !operation.hasInsertionGuard {
            throw StandardEditViolation.insertion_requires_guard(
                operationIndex: operationIndex,
                operation: operation.kind
            )
        }
    }
}

public extension StandardEditBudget {
    func validate(
        _ report: StandardEditReport
    ) throws {
        if let limit = operations.value,
           !operations.allows(
               report.counts.operations
           ) {
            throw StandardEditViolation.operations_exceeded(
                actual: report.counts.operations,
                limit: limit
            )
        }

        if let limit = changed.value,
           !changed.allows(
               report.counts.changed
           ) {
            throw StandardEditViolation.changed_exceeded(
                actual: report.counts.changed,
                limit: limit
            )
        }

        if let limit = inserted.value,
           !inserted.allows(
               report.counts.inserted
           ) {
            throw StandardEditViolation.inserted_exceeded(
                actual: report.counts.inserted,
                limit: limit
            )
        }

        if let limit = deleted.value,
           !deleted.allows(
               report.counts.deleted
           ) {
            throw StandardEditViolation.deleted_exceeded(
                actual: report.counts.deleted,
                limit: limit
            )
        }

        if let limit = span.value,
           !span.allows(
               report.span.max
           ) {
            throw StandardEditViolation.span_exceeded(
                actual: report.span.max,
                limit: limit
            )
        }
    }
}

public extension StandardEditScope {
    func validateOriginalRanges(
        _ ranges: [LineRange]
    ) throws {
        switch self {
        case .file:
            return

        case .lines(let allowed):
            for range in ranges {
                guard contains(
                    range,
                    in: allowed
                ) else {
                    throw StandardEditViolation.original_range_outside_scope(
                        range: range,
                        scope: self
                    )
                }
            }

        case .insertions:
            for range in ranges {
                throw StandardEditViolation.original_range_outside_scope(
                    range: range,
                    scope: self
                )
            }
        }
    }

    func validateEditedRanges(
        _ ranges: [LineRange]
    ) throws {
        switch self {
        case .file:
            return

        case .lines(let allowed):
            for range in ranges {
                guard contains(
                    range,
                    in: allowed
                ) else {
                    throw StandardEditViolation.edited_range_outside_scope(
                        range: range,
                        scope: self
                    )
                }
            }

        case .insertions(let positions):
            for range in ranges {
                guard positions.contains(
                    range.start
                ) else {
                    throw StandardEditViolation.edited_range_outside_scope(
                        range: range,
                        scope: self
                    )
                }
            }
        }
    }

    func validate(
        operation: StandardEditOperation,
        operationIndex: Int
    ) throws {
        switch self {
        case .file:
            return

        case .lines(let allowed):
            try validateLineScopedOperation(
                operation,
                operationIndex: operationIndex,
                allowed: allowed
            )

        case .insertions(let positions):
            try validateInsertionScopedOperation(
                operation,
                operationIndex: operationIndex,
                positions: positions
            )
        }
    }
}

private extension StandardEditScope {
    func validateLineScopedOperation(
        _ operation: StandardEditOperation,
        operationIndex: Int,
        allowed: [LineRange]
    ) throws {
        switch operation {
        case .replaceEntireFile,
             .append,
             .prepend:
            throw StandardEditViolation.operation_outside_scope(
                operationIndex: operationIndex,
                operation: operation.kind,
                scope: self
            )

        case .replaceLine(let line, _),
             .replaceLineGuarded(let line, _, _):
            try validateLine(
                line,
                operation: operation,
                operationIndex: operationIndex,
                allowed: allowed
            )

        case .insertLines(_, let line),
             .insertLinesGuarded(_, let line, _):
            try validateLine(
                line,
                operation: operation,
                operationIndex: operationIndex,
                allowed: allowed
            )

        case .replaceLines(let range, _),
             .replaceLinesGuarded(let range, _, _),
             .deleteLines(let range),
             .deleteLinesGuarded(let range, _):
            guard contains(
                range,
                in: allowed
            ) else {
                throw StandardEditViolation.operation_outside_scope(
                    operationIndex: operationIndex,
                    operation: operation.kind,
                    scope: self
                )
            }

        case .replaceFirst,
             .replaceAll,
             .replaceUnique:
            return
        }
    }

    func validateInsertionScopedOperation(
        _ operation: StandardEditOperation,
        operationIndex: Int,
        positions: [Int]
    ) throws {
        switch operation {
        case .insertLines(_, let line),
             .insertLinesGuarded(_, let line, _):
            guard positions.contains(line) else {
                throw StandardEditViolation.operation_outside_scope(
                    operationIndex: operationIndex,
                    operation: operation.kind,
                    scope: self
                )
            }

        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique,
             .replaceLine,
             .replaceLineGuarded,
             .replaceLines,
             .replaceLinesGuarded,
             .deleteLines,
             .deleteLinesGuarded:
            throw StandardEditViolation.operation_outside_scope(
                operationIndex: operationIndex,
                operation: operation.kind,
                scope: self
            )
        }
    }

    func validateLine(
        _ line: Int,
        operation: StandardEditOperation,
        operationIndex: Int,
        allowed: [LineRange]
    ) throws {
        let range = LineRange(
            uncheckedStart: line,
            uncheckedEnd: line
        )

        guard contains(
            range,
            in: allowed
        ) else {
            throw StandardEditViolation.operation_outside_scope(
                operationIndex: operationIndex,
                operation: operation.kind,
                scope: self
            )
        }
    }

    func contains(
        _ range: LineRange,
        in allowed: [LineRange]
    ) -> Bool {
        allowed.contains { candidate in
            candidate.start <= range.start
                && candidate.end >= range.end
        }
    }
}
