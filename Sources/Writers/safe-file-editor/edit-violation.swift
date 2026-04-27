import Foundation
import Position

public enum StandardEditViolationCode: String, Sendable, Codable, Hashable, CaseIterable {
    case operations_exceeded
    case changed_exceeded
    case inserted_exceeded
    case deleted_exceeded
    case span_exceeded
    case operation_not_allowed
    case operation_requires_guard
    case insertion_requires_guard
    case unguardable_operation_denied
    case original_range_outside_scope
    case edited_range_outside_scope
    case operation_outside_scope
}

public enum StandardEditRecoveryHint: String, Sendable, Codable, Hashable, CaseIterable {
    case use_smaller_range
    case split_into_multiple_edits
    case re_read_file
    case use_guarded_operation
    case use_guarded_insertion
    case request_larger_scope
    case request_larger_budget
    case use_insert_lines_only
    case use_precise_line_operation
    case use_snapshot_mode
}

public enum StandardEditViolation: Error, Sendable, LocalizedError, Hashable {
    case operations_exceeded(
        actual: Int,
        limit: Int
    )
    case changed_exceeded(
        actual: Int,
        limit: Int
    )
    case inserted_exceeded(
        actual: Int,
        limit: Int
    )
    case deleted_exceeded(
        actual: Int,
        limit: Int
    )
    case span_exceeded(
        actual: Int,
        limit: Int
    )
    case operation_not_allowed(
        operationIndex: Int,
        operation: StandardEditOperationKind,
        allowed: Set<StandardEditOperationKind>
    )
    case operation_requires_guard(
        operationIndex: Int,
        operation: StandardEditOperationKind
    )
    case insertion_requires_guard(
        operationIndex: Int,
        operation: StandardEditOperationKind
    )
    case unguardable_operation_denied(
        operationIndex: Int,
        operation: StandardEditOperationKind
    )
    case original_range_outside_scope(
        range: LineRange,
        scope: StandardEditScope
    )
    case edited_range_outside_scope(
        range: LineRange,
        scope: StandardEditScope
    )
    case operation_outside_scope(
        operationIndex: Int,
        operation: StandardEditOperationKind,
        scope: StandardEditScope
    )

    public var code: StandardEditViolationCode {
        switch self {
        case .operations_exceeded:
            return .operations_exceeded

        case .changed_exceeded:
            return .changed_exceeded

        case .inserted_exceeded:
            return .inserted_exceeded

        case .deleted_exceeded:
            return .deleted_exceeded

        case .span_exceeded:
            return .span_exceeded

        case .operation_not_allowed:
            return .operation_not_allowed

        case .operation_requires_guard:
            return .operation_requires_guard

        case .insertion_requires_guard:
            return .insertion_requires_guard

        case .unguardable_operation_denied:
            return .unguardable_operation_denied

        case .original_range_outside_scope:
            return .original_range_outside_scope

        case .edited_range_outside_scope:
            return .edited_range_outside_scope

        case .operation_outside_scope:
            return .operation_outside_scope
        }
    }

    public var hints: [StandardEditRecoveryHint] {
        switch self {
        case .operations_exceeded:
            return [
                .split_into_multiple_edits,
                .request_larger_budget,
            ]

        case .changed_exceeded,
             .inserted_exceeded,
             .deleted_exceeded,
             .span_exceeded:
            return [
                .use_smaller_range,
                .split_into_multiple_edits,
                .request_larger_budget,
            ]

        case .operation_not_allowed:
            return [
                .use_precise_line_operation,
                .use_guarded_operation,
            ]

        case .operation_requires_guard:
            return [
                .use_guarded_operation,
                .re_read_file,
            ]

        case .insertion_requires_guard:
            return [
                .use_guarded_insertion,
                .re_read_file,
            ]

        case .unguardable_operation_denied:
            return [
                .use_precise_line_operation,
                .use_snapshot_mode,
            ]

        case .original_range_outside_scope,
             .edited_range_outside_scope,
             .operation_outside_scope:
            return [
                .request_larger_scope,
                .re_read_file,
            ]
        }
    }

    public var errorDescription: String? {
        switch self {
        case .operations_exceeded(let actual, let limit):
            return "Edit operation count \(actual) exceeds budget \(limit)."

        case .changed_exceeded(let actual, let limit):
            return "Edit changed line count \(actual) exceeds budget \(limit)."

        case .inserted_exceeded(let actual, let limit):
            return "Edit inserted line count \(actual) exceeds budget \(limit)."

        case .deleted_exceeded(let actual, let limit):
            return "Edit deleted line count \(actual) exceeds budget \(limit)."

        case .span_exceeded(let actual, let limit):
            return "Edit replacement span \(actual) exceeds budget \(limit)."

        case .operation_not_allowed(let operationIndex, let operation, let allowed):
            let allowedNames = allowed
                .map(\.rawValue)
                .sorted()
                .joined(
                    separator: ", "
                )

            return "Edit operation \(operationIndex) '\(operation.rawValue)' is not allowed. Allowed operations: \(allowedNames)."

        case .operation_requires_guard(let operationIndex, let operation):
            return "Edit operation \(operationIndex) '\(operation.rawValue)' requires a guarded line operation."

        case .insertion_requires_guard(let operationIndex, let operation):
            return "Edit operation \(operationIndex) '\(operation.rawValue)' requires a guarded insertion site."

        case .unguardable_operation_denied(let operationIndex, let operation):
            return "Edit operation \(operationIndex) '\(operation.rawValue)' cannot be guarded and is denied by this constraint."

        case .original_range_outside_scope(let range, let scope):
            return "Edit original range \(range.start)...\(range.end) is outside scope \(scope)."

        case .edited_range_outside_scope(let range, let scope):
            return "Edit edited range \(range.start)...\(range.end) is outside scope \(scope)."

        case .operation_outside_scope(let operationIndex, let operation, let scope):
            return "Edit operation \(operationIndex) '\(operation.rawValue)' is outside scope \(scope)."
        }
    }
}
