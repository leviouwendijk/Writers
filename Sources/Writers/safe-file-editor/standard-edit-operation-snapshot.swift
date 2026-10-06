import Foundation
import Position

public enum StandardEditSnapshotError: Error, LocalizedError, Sendable {
    case unsupportedOperation(
        index: Int,
        operation: String
    )

    case replaceEntireFileMustBeOnlyOperation(
        index: Int
    )

    case overlappingRanges(
        firstIndex: Int,
        secondIndex: Int,
        firstRange: LineRange,
        secondRange: LineRange
    )

    case insertionInsideEditedRange(
        insertionIndex: Int,
        insertionLine: Int,
        rangeIndex: Int,
        range: LineRange
    )

    case mixedCoordinateFamilies

    case overlappingPositionRanges(
        firstIndex: Int,
        secondIndex: Int,
        firstRange: PositionRange,
        secondRange: PositionRange
    )

    public var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let index, let operation):
            return "Snapshot edit operation \(index) is not supported by the line-snapshot planner: \(operation). Use sequential edit semantics for text-search operations."

        case .replaceEntireFileMustBeOnlyOperation(let index):
            return "Snapshot edit operation \(index) replaces the entire file and must be the only operation in the plan."

        case .overlappingRanges(let firstIndex, let secondIndex, let firstRange, let secondRange):
            return "Snapshot edit operations \(firstIndex) and \(secondIndex) edit overlapping original line ranges: \(firstRange) and \(secondRange)."

        case .insertionInsideEditedRange(let insertionIndex, let insertionLine, let rangeIndex, let range):
            return "Snapshot edit operation \(insertionIndex) inserts at original line \(insertionLine), which is inside the original range edited by operation \(rangeIndex): \(range)."

        case .mixedCoordinateFamilies:
            return "Snapshot edits may not mix PositionRange replacement with other coordinate families."

        case .overlappingPositionRanges(let firstIndex, let secondIndex, let firstRange, let secondRange):
            return "Snapshot edit operations \(firstIndex) and \(secondIndex) edit overlapping original position ranges: \(firstRange) and \(secondRange)."
        }
    }
}

private struct StandardEditSnapshotRangeEdit: Sendable {
    let operationIndex: Int
    let range: PositionRange
    let replacement: String
}

private struct StandardEditSnapshotLineEdit: Sendable {
    let operationIndex: Int
    let startIndex: Int
    let endIndex: Int
    let replacementLines: [String]
    let originalRange: LineRange?

    var removedCount: Int {
        endIndex - startIndex
    }

    var isInsertion: Bool {
        removedCount == 0
    }

    var insertionLine: Int {
        startIndex + 1
    }

    var requiredRange: LineRange {
        originalRange ?? .init(
            uncheckedStart: insertionLine,
            uncheckedEnd: insertionLine
        )
    }
}

public extension StandardEditOperation {
    func applyingSnapshot(
        to content: String
    ) throws -> String {
        try Self.applyingSnapshot(
            [
                self,
            ],
            to: content
        )
    }

    static func applyingSnapshot(
        _ operations: [Self],
        to content: String
    ) throws -> String {
        guard !operations.isEmpty else {
            return content
        }

        if operations.count == 1,
           case .replaceEntireFile = operations[0] {
            return try operations[0].applying(
                to: content
            )
        }

        if operations.containsReplaceEntireFile {
            let index = operations.firstReplaceEntireFileIndex ?? 1
            throw StandardEditSnapshotError.replaceEntireFileMustBeOnlyOperation(
                index: index
            )
        }

        if operations.containsPositionRangeOperation {
            guard operations.allSatisfy({ $0.isPositionRangeOperation }) else {
                throw StandardEditSnapshotError.mixedCoordinateFamilies
            }

            return try applyingSnapshotPositionRanges(
                operations,
                to: content
            )
        }

        let originalLines = WriteTextLines(
            content
        ).lines

        let edits = try operations.enumerated().map { offset, operation in
            try snapshotLineEdit(
                operation,
                operationIndex: offset + 1,
                originalLines: originalLines
            )
        }

        try validateSnapshotConflicts(
            edits
        )

        return WriteTextLines.string(
            applySnapshotLineEdits(
                edits,
                to: originalLines
            )
        )
    }

    private static func snapshotLineEdit(
        _ operation: Self,
        operationIndex: Int,
        originalLines: [String]
    ) throws -> StandardEditSnapshotLineEdit {
        switch operation {
        case .replaceEntireFile:
            throw StandardEditSnapshotError.replaceEntireFileMustBeOnlyOperation(
                index: operationIndex
            )

        case .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique,
             .replaceRange,
             .replaceRangeGuarded:
            throw StandardEditSnapshotError.unsupportedOperation(
                index: operationIndex,
                operation: operation.snapshotDescription
            )

        case .replaceLine(let line, let replacement):
            try validateSnapshotLogicalLine(
                replacement
            )
            try validateSnapshotExistingLine(
                line,
                in: originalLines
            )

            let range = LineRange(
                uncheckedStart: line,
                uncheckedEnd: line
            )

            return .init(
                operationIndex: operationIndex,
                startIndex: line - 1,
                endIndex: line,
                replacementLines: [
                    replacement,
                ],
                originalRange: range
            )

        case .replaceLineGuarded(let line, let expected, let replacement):
            try validateSnapshotLogicalLine(
                expected
            )
            try validateSnapshotLogicalLine(
                replacement
            )
            try validateSnapshotExistingLine(
                line,
                in: originalLines
            )

            let actual = originalLines[line - 1]

            guard actual == expected else {
                throw StandardEditError.lineMismatch(
                    line: line,
                    expected: expected,
                    actual: actual
                )
            }

            let range = LineRange(
                uncheckedStart: line,
                uncheckedEnd: line
            )

            return .init(
                operationIndex: operationIndex,
                startIndex: line - 1,
                endIndex: line,
                replacementLines: [
                    replacement,
                ],
                originalRange: range
            )

        case .insertLines(let insertedLines, let line):
            try validateSnapshotLogicalLines(
                insertedLines
            )
            try validateSnapshotInsertionLine(
                line,
                in: originalLines
            )

            return .init(
                operationIndex: operationIndex,
                startIndex: line - 1,
                endIndex: line - 1,
                replacementLines: insertedLines,
                originalRange: nil
            )

        case .insertLinesGuarded(let insertedLines, let line, let site):
            try validateSnapshotLogicalLines(
                insertedLines
            )
            try validateSnapshotLogicalLines(
                site.before
            )
            try validateSnapshotLogicalLines(
                site.after
            )
            try validateSnapshotInsertionLine(
                line,
                in: originalLines
            )
            try validateSnapshotInsertionSite(
                line,
                site: site,
                in: originalLines
            )

            return .init(
                operationIndex: operationIndex,
                startIndex: line - 1,
                endIndex: line - 1,
                replacementLines: insertedLines,
                originalRange: nil
            )

        case .replaceLines(let range, let replacementLines):
            try validateSnapshotLogicalLines(
                replacementLines
            )
            try validateSnapshotExistingRange(
                range,
                in: originalLines
            )

            return .init(
                operationIndex: operationIndex,
                startIndex: range.start - 1,
                endIndex: range.end,
                replacementLines: replacementLines,
                originalRange: range
            )

        case .replaceLinesGuarded(let range, let expectedLines, let replacementLines):
            try validateSnapshotLogicalLines(
                expectedLines
            )
            try validateSnapshotLogicalLines(
                replacementLines
            )
            try validateSnapshotExistingRange(
                range,
                in: originalLines
            )

            let actualLines = Array(
                originalLines[(range.start - 1)..<range.end]
            )

            guard actualLines == expectedLines else {
                throw StandardEditError.lineRangeMismatch(
                    range: range,
                    expected: expectedLines,
                    actual: actualLines
                )
            }

            return .init(
                operationIndex: operationIndex,
                startIndex: range.start - 1,
                endIndex: range.end,
                replacementLines: replacementLines,
                originalRange: range
            )

        case .deleteLines(let range):
            try validateSnapshotExistingRange(
                range,
                in: originalLines
            )

            return .init(
                operationIndex: operationIndex,
                startIndex: range.start - 1,
                endIndex: range.end,
                replacementLines: [],
                originalRange: range
            )

        case .deleteLinesGuarded(let range, let expectedLines):
            try validateSnapshotLogicalLines(
                expectedLines
            )
            try validateSnapshotExistingRange(
                range,
                in: originalLines
            )

            let actualLines = Array(
                originalLines[(range.start - 1)..<range.end]
            )

            guard actualLines == expectedLines else {
                throw StandardEditError.lineRangeMismatch(
                    range: range,
                    expected: expectedLines,
                    actual: actualLines
                )
            }

            return .init(
                operationIndex: operationIndex,
                startIndex: range.start - 1,
                endIndex: range.end,
                replacementLines: [],
                originalRange: range
            )
        }
    }

    private static func applyingSnapshotPositionRanges(
        _ operations: [Self],
        to content: String
    ) throws -> String {
        let edits = try operations.enumerated().map { offset, operation in
            try snapshotRangeEdit(
                operation,
                operationIndex: offset + 1,
                content: content
            )
        }

        let sorted = edits.sorted { lhs, rhs in
            if lhs.range.start != rhs.range.start {
                return lhs.range.start < rhs.range.start
            }

            return lhs.range.end < rhs.range.end
        }

        var previous: StandardEditSnapshotRangeEdit?

        for edit in sorted {
            if let previous,
               edit.range.start.offset < previous.range.end.offset {
                throw StandardEditSnapshotError.overlappingPositionRanges(
                    firstIndex: previous.operationIndex,
                    secondIndex: edit.operationIndex,
                    firstRange: previous.range,
                    secondRange: edit.range
                )
            }

            previous = edit
        }

        var edited = content

        for edit in edits.sorted(by: { lhs, rhs in
            lhs.range.start > rhs.range.start
        }) {
            let resolved = try resolvePositionRange(
                edit.range,
                in: edited
            )

            edited.replaceSubrange(
                resolved,
                with: edit.replacement
            )
        }

        return edited
    }

    private static func snapshotRangeEdit(
        _ operation: Self,
        operationIndex: Int,
        content: String
    ) throws -> StandardEditSnapshotRangeEdit {
        switch operation {
        case .replaceRange(let range, let replacement):
            _ = try resolvePositionRange(
                range,
                in: content
            )

            return .init(
                operationIndex: operationIndex,
                range: range,
                replacement: replacement
            )

        case .replaceRangeGuarded(let range, let expected, let replacement):
            let resolved = try resolvePositionRange(
                range,
                in: content
            )
            let actual = String(
                content[resolved]
            )

            guard actual == expected else {
                throw StandardEditError.positionRangeMismatch(
                    range: range,
                    expected: expected,
                    actual: actual
                )
            }

            return .init(
                operationIndex: operationIndex,
                range: range,
                replacement: replacement
            )

        default:
            throw StandardEditSnapshotError.mixedCoordinateFamilies
        }
    }

    private static func validateSnapshotConflicts(
        _ edits: [StandardEditSnapshotLineEdit]
    ) throws {
        let rangedEdits = edits
            .filter { !$0.isInsertion }
            .sorted {
                if $0.startIndex != $1.startIndex {
                    return $0.startIndex < $1.startIndex
                }

                return $0.endIndex < $1.endIndex
            }

        var previous: StandardEditSnapshotLineEdit?

        for edit in rangedEdits {
            if let previous,
               edit.startIndex < previous.endIndex {
                throw StandardEditSnapshotError.overlappingRanges(
                    firstIndex: previous.operationIndex,
                    secondIndex: edit.operationIndex,
                    firstRange: previous.requiredRange,
                    secondRange: edit.requiredRange
                )
            }

            previous = edit
        }

        for insertion in edits where insertion.isInsertion {
            for rangeEdit in rangedEdits {
                guard rangeEdit.startIndex < insertion.startIndex,
                      insertion.startIndex < rangeEdit.endIndex
                else {
                    continue
                }

                throw StandardEditSnapshotError.insertionInsideEditedRange(
                    insertionIndex: insertion.operationIndex,
                    insertionLine: insertion.insertionLine,
                    rangeIndex: rangeEdit.operationIndex,
                    range: rangeEdit.requiredRange
                )
            }
        }
    }

    private static func applySnapshotLineEdits(
        _ edits: [StandardEditSnapshotLineEdit],
        to originalLines: [String]
    ) -> [String] {
        let insertionsBySite = Dictionary(
            grouping: edits.filter(\.isInsertion),
            by: \.startIndex
        )

        let replacementsByStart = Dictionary(
            uniqueKeysWithValues: edits
                .filter { !$0.isInsertion }
                .map { edit in
                    (
                        edit.startIndex,
                        edit
                    )
                }
        )

        var out: [String] = []
        var cursor = 0

        while cursor < originalLines.count {
            if let insertions = insertionsBySite[cursor] {
                for insertion in insertions.sorted(by: operationSort) {
                    out.append(
                        contentsOf: insertion.replacementLines
                    )
                }
            }

            if let replacement = replacementsByStart[cursor] {
                out.append(
                    contentsOf: replacement.replacementLines
                )
                cursor = replacement.endIndex
            } else {
                out.append(
                    originalLines[cursor]
                )
                cursor += 1
            }
        }

        if let insertions = insertionsBySite[originalLines.count] {
            for insertion in insertions.sorted(by: operationSort) {
                out.append(
                    contentsOf: insertion.replacementLines
                )
            }
        }

        return out
    }

    private static func operationSort(
        _ lhs: StandardEditSnapshotLineEdit,
        _ rhs: StandardEditSnapshotLineEdit
    ) -> Bool {
        lhs.operationIndex < rhs.operationIndex
    }

    private static func validateSnapshotLogicalLines(
        _ lines: [String]
    ) throws {
        for line in lines {
            try validateSnapshotLogicalLine(
                line
            )
        }
    }

    private static func validateSnapshotLogicalLine(
        _ line: String
    ) throws {
        guard !line.contains("\n"),
              !line.contains("\r")
        else {
            throw StandardEditError.invalidLogicalLine(
                line
            )
        }
    }

    private static func validateSnapshotExistingLine(
        _ line: Int,
        in lines: [String]
    ) throws {
        guard let valid = validSnapshotExistingLineRange(
            for: lines
        ) else {
            throw StandardEditError.lineOutOfBounds(
                line,
                valid: nil
            )
        }

        guard valid.contains(line) else {
            throw StandardEditError.lineOutOfBounds(
                line,
                valid: valid
            )
        }
    }

    private static func validateSnapshotExistingRange(
        _ range: LineRange,
        in lines: [String]
    ) throws {
        guard let valid = validSnapshotExistingLineRange(
            for: lines
        ) else {
            throw StandardEditError.lineRangeOutOfBounds(
                range,
                valid: nil
            )
        }

        guard range.start <= range.end,
              valid.contains(range.start),
              valid.contains(range.end)
        else {
            throw StandardEditError.lineRangeOutOfBounds(
                range,
                valid: valid
            )
        }
    }

    private static func validateSnapshotInsertionLine(
        _ line: Int,
        in lines: [String]
    ) throws {
        let valid = validSnapshotInsertionLineRange(
            for: lines
        )

        guard valid.contains(line) else {
            throw StandardEditError.insertionLineOutOfBounds(
                line,
                valid: valid
            )
        }
    }

    private static func validateSnapshotInsertionSite(
        _ line: Int,
        site: StandardEditSiteGuard,
        in lines: [String]
    ) throws {
        let index = line - 1

        let beforeLowerBound = max(
            0,
            index - site.before.count
        )
        let beforeUpperBound = index

        let actualBefore = Array(
            lines[beforeLowerBound..<beforeUpperBound]
        )

        let afterLowerBound = index
        let afterUpperBound = min(
            lines.count,
            index + site.after.count
        )

        let actualAfter = Array(
            lines[afterLowerBound..<afterUpperBound]
        )

        guard actualBefore == site.before,
              actualAfter == site.after
        else {
            throw StandardEditError.insertionSiteMismatch(
                line: line,
                expectedBefore: site.before,
                actualBefore: actualBefore,
                expectedAfter: site.after,
                actualAfter: actualAfter
            )
        }
    }

    private static func validSnapshotExistingLineRange(
        for lines: [String]
    ) -> ClosedRange<Int>? {
        guard !lines.isEmpty else {
            return nil
        }

        return 1...lines.count
    }

    private static func validSnapshotInsertionLineRange(
        for lines: [String]
    ) -> ClosedRange<Int> {
        1...max(
            1,
            lines.count + 1
        )
    }

    private var snapshotDescription: String {
        switch self {
        case .replaceEntireFile:
            return "replaceEntireFile"

        case .append:
            return "append"

        case .prepend:
            return "prepend"

        case .replaceFirst:
            return "replaceFirst"

        case .replaceAll:
            return "replaceAll"

        case .replaceUnique:
            return "replaceUnique"

        case .replaceRange:
            return "replaceRange"

        case .replaceRangeGuarded:
            return "replaceRangeGuarded"

        case .replaceLine:
            return "replaceLine"

        case .replaceLineGuarded:
            return "replaceLineGuarded"

        case .insertLines:
            return "insertLines"

        case .insertLinesGuarded:
            return "insertLinesGuarded"

        case .replaceLines:
            return "replaceLines"

        case .replaceLinesGuarded:
            return "replaceLinesGuarded"

        case .deleteLines:
            return "deleteLines"

        case .deleteLinesGuarded:
            return "deleteLinesGuarded"
        }
    }

    // private static var empty: [Self] {
    //     []
    // }
}

private extension StandardEditOperation {
    var isPositionRangeOperation: Bool {
        switch self {
        case .replaceRange,
             .replaceRangeGuarded:
            return true

        default:
            return false
        }
    }
}

private extension Array where Element == StandardEditOperation {
    var containsPositionRangeOperation: Bool {
        contains { $0.isPositionRangeOperation }
    }

    var containsReplaceEntireFile: Bool {
        contains { operation in
            if case .replaceEntireFile = operation {
                return true
            }

            return false
        }
    }

    var firstReplaceEntireFileIndex: Int? {
        firstIndex { operation in
            if case .replaceEntireFile = operation {
                return true
            }

            return false
        }
        .map { $0 + 1 }
    }
}
