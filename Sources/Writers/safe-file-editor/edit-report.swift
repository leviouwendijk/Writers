import Foundation
import Position

public struct StandardEditCounts: Sendable, Codable, Hashable {
    public var operations: Int
    public var changed: Int
    public var inserted: Int
    public var deleted: Int

    public init(
        operations: Int,
        changed: Int,
        inserted: Int,
        deleted: Int
    ) {
        self.operations = operations
        self.changed = changed
        self.inserted = inserted
        self.deleted = deleted
    }
}

public struct StandardEditSpan: Sendable, Codable, Hashable {
    public var original: Int
    public var edited: Int

    public init(
        original: Int,
        edited: Int
    ) {
        self.original = original
        self.edited = edited
    }

    public var max: Int {
        Swift.max(
            original,
            edited
        )
    }
}

public struct StandardEditReport: Sendable, Codable, Hashable {
    public var target: URL
    public var operations: [StandardEditOperationKind]
    public var counts: StandardEditCounts
    public var originalRanges: [LineRange]
    public var editedRanges: [LineRange]
    public var span: StandardEditSpan
    public var rollbackOperationCount: Int

    public init(
        target: URL,
        operations: [StandardEditOperationKind],
        counts: StandardEditCounts,
        originalRanges: [LineRange],
        editedRanges: [LineRange],
        span: StandardEditSpan,
        rollbackOperationCount: Int
    ) {
        self.target = target
        self.operations = operations
        self.counts = counts
        self.originalRanges = originalRanges
        self.editedRanges = editedRanges
        self.span = span
        self.rollbackOperationCount = rollbackOperationCount
    }

    public init(
        _ result: StandardEditResult
    ) {
        let originalRanges = result.originalChangedLineRanges
        let editedRanges = result.editedChangedLineRanges

        self.init(
            target: result.target,
            operations: result.operations.map(\.kind),
            counts: .init(
                operations: result.operations.count,
                changed: result.changeCount,
                inserted: result.insertions,
                deleted: result.deletions
            ),
            originalRanges: originalRanges,
            editedRanges: editedRanges,
            span: .init(
                original: originalRanges.maxLineCount,
                edited: editedRanges.maxLineCount
            ),
            rollbackOperationCount: result.rollbackOperations.count
        )
    }

    public var hasWideOperation: Bool {
        operations.contains { operation in
            switch operation {
            case .replace_entire_file,
                 .append,
                 .prepend,
                 .replace_all:
                return true

            case .replace_first,
                 .replace_unique,
                 .replace_line,
                 .replace_line_guarded,
                 .insert_lines,
                 .insert_lines_guarded,
                 .replace_lines,
                 .replace_lines_guarded,
                 .delete_lines,
                 .delete_lines_guarded:
                return false
            }
        }
    }

    public var hasTextOperation: Bool {
        operations.contains { operation in
            switch operation {
            case .replace_first,
                 .replace_all,
                 .replace_unique:
                return true

            case .replace_entire_file,
                 .append,
                 .prepend,
                 .replace_line,
                 .replace_line_guarded,
                 .insert_lines,
                 .insert_lines_guarded,
                 .replace_lines,
                 .replace_lines_guarded,
                 .delete_lines,
                 .delete_lines_guarded:
                return false
            }
        }
    }
}

public extension StandardEditResult {
    var report: StandardEditReport {
        .init(
            self
        )
    }
}

private extension Array where Element == LineRange {
    var maxLineCount: Int {
        map(\.lineCount).max() ?? 0
    }
}

private extension LineRange {
    var lineCount: Int {
        max(
            0,
            end - start + 1
        )
    }
}
