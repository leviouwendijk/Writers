import Foundation
import Position

public extension StandardEditOperation {
    func applying(
        to content: String
    ) throws -> String {
        switch self {
        case .replaceEntireFile(let replacement):
            return replacement

        case .append(let suffix, let separator):
            guard !content.isEmpty else {
                return suffix
            }

            guard let separator, !separator.isEmpty else {
                return content + suffix
            }

            return content + separator + suffix

        case .prepend(let prefix, let separator):
            guard !content.isEmpty else {
                return prefix
            }

            guard let separator, !separator.isEmpty else {
                return prefix + content
            }

            return prefix + separator + content

        case .replaceFirst(let needle, let replacement):
            let needle = try Self.validatedNeedle(
                needle
            )

            guard let range = content.range(
                of: needle
            ) else {
                throw StandardEditError.matchNotFound(
                    needle
                )
            }

            var edited = content
            edited.replaceSubrange(
                range,
                with: replacement
            )
            return edited

        case .replaceAll(let needle, let replacement):
            let needle = try Self.validatedNeedle(
                needle
            )

            let count = Self.occurrenceCount(
                of: needle,
                in: content
            )

            guard count > 0 else {
                throw StandardEditError.matchNotFound(
                    needle
                )
            }

            return content.replacingOccurrences(
                of: needle,
                with: replacement
            )

        case .replaceUnique(let needle, let replacement):
            let needle = try Self.validatedNeedle(
                needle
            )

            let count = Self.occurrenceCount(
                of: needle,
                in: content
            )

            guard count > 0 else {
                throw StandardEditError.matchNotFound(
                    needle
                )
            }

            guard count == 1 else {
                throw StandardEditError.matchNotUnique(
                    needle,
                    count: count
                )
            }

            guard let range = content.range(
                of: needle
            ) else {
                throw StandardEditError.matchNotFound(
                    needle
                )
            }

            var edited = content
            edited.replaceSubrange(
                range,
                with: replacement
            )
            return edited

        case .replaceLine(let line, let replacement):
            try Self.validateLogicalLine(
                replacement
            )

            var lines = WriteTextLines(
                content
            ).lines

            try Self.validateExistingLine(
                line,
                in: lines
            )

            lines[line - 1] = replacement
            return WriteTextLines.string(
                lines
            )

        case .replaceLineGuarded(let line, let expected, let replacement):
            try Self.validateLogicalLine(
                expected
            )
            try Self.validateLogicalLine(
                replacement
            )

            var lines = WriteTextLines(
                content
            ).lines

            try Self.validateExistingLine(
                line,
                in: lines
            )

            let actual = lines[line - 1]

            guard actual == expected else {
                throw StandardEditError.lineMismatch(
                    line: line,
                    expected: expected,
                    actual: actual
                )
            }

            lines[line - 1] = replacement
            return WriteTextLines.string(
                lines
            )

        case .insertLines(let insertedLines, let line):
            try Self.validateLogicalLines(
                insertedLines
            )

            var lines = WriteTextLines(
                content
            ).lines

            try Self.validateInsertionLine(
                line,
                in: lines
            )

            guard !insertedLines.isEmpty else {
                return content
            }

            lines.insert(
                contentsOf: insertedLines,
                at: line - 1
            )

            return WriteTextLines.string(
                lines
            )

        case .insertLinesGuarded(let insertedLines, let line, let site):
            try Self.validateLogicalLines(
                insertedLines
            )
            try Self.validateLogicalLines(
                site.before
            )
            try Self.validateLogicalLines(
                site.after
            )

            var lines = WriteTextLines(
                content
            ).lines

            try Self.validateInsertionLine(
                line,
                in: lines
            )
            try Self.validateInsertionSite(
                line,
                site: site,
                in: lines
            )

            guard !insertedLines.isEmpty else {
                return content
            }

            lines.insert(
                contentsOf: insertedLines,
                at: line - 1
            )

            return WriteTextLines.string(
                lines
            )

        case .replaceLines(let range, let replacementLines):
            try Self.validateLogicalLines(
                replacementLines
            )

            var lines = WriteTextLines(
                content
            ).lines

            try Self.validateExistingRange(
                range,
                in: lines
            )

            lines.replaceSubrange(
                (range.start - 1)..<range.end,
                with: replacementLines
            )

            return WriteTextLines.string(
                lines
            )

        case .replaceLinesGuarded(let range, let expectedLines, let replacementLines):
            try Self.validateLogicalLines(
                expectedLines
            )
            try Self.validateLogicalLines(
                replacementLines
            )

            var lines = WriteTextLines(
                content
            ).lines

            try Self.validateExistingRange(
                range,
                in: lines
            )

            let actualLines = Self.lines(
                in: range,
                from: lines
            )

            guard actualLines == expectedLines else {
                throw StandardEditError.lineRangeMismatch(
                    range: range,
                    expected: expectedLines,
                    actual: actualLines
                )
            }

            lines.replaceSubrange(
                (range.start - 1)..<range.end,
                with: replacementLines
            )

            return WriteTextLines.string(
                lines
            )

        case .deleteLines(let range):
            var lines = WriteTextLines(
                content
            ).lines

            try Self.validateExistingRange(
                range,
                in: lines
            )

            lines.removeSubrange(
                (range.start - 1)..<range.end
            )

            return WriteTextLines.string(
                lines
            )

        case .deleteLinesGuarded(let range, let expectedLines):
            try Self.validateLogicalLines(
                expectedLines
            )

            var lines = WriteTextLines(
                content
            ).lines

            try Self.validateExistingRange(
                range,
                in: lines
            )

            let actualLines = Self.lines(
                in: range,
                from: lines
            )

            guard actualLines == expectedLines else {
                throw StandardEditError.lineRangeMismatch(
                    range: range,
                    expected: expectedLines,
                    actual: actualLines
                )
            }

            lines.removeSubrange(
                (range.start - 1)..<range.end
            )

            return WriteTextLines.string(
                lines
            )
        }
    }

    static func applying(
        _ operations: [Self],
        to content: String,
        mode: StandardEditMode = .sequential
    ) throws -> String {
        switch mode {
        case .sequential:
            return try applyingSequential(
                operations,
                to: content
            )

        case .snapshot:
            return try applyingSnapshot(
                operations,
                to: content
            )
        }
    }

    private static func validatedNeedle(
        _ needle: String
    ) throws -> String {
        guard !needle.isEmpty else {
            throw StandardEditError.emptyMatchString
        }

        return needle
    }

    private static func occurrenceCount(
        of needle: String,
        in haystack: String
    ) -> Int {
        guard !needle.isEmpty else {
            return 0
        }

        var count = 0
        var searchStart = haystack.startIndex

        while searchStart < haystack.endIndex,
              let range = haystack.range(
                of: needle,
                range: searchStart..<haystack.endIndex
              ) {
            count += 1
            searchStart = range.upperBound
        }

        return count
    }

    private static func validateLogicalLines(
        _ lines: [String]
    ) throws {
        for line in lines {
            try validateLogicalLine(
                line
            )
        }
    }

    private static func validateLogicalLine(
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

    private static func lines(
        in range: LineRange,
        from lines: [String]
    ) -> [String] {
        Array(
            lines[(range.start - 1)..<range.end]
        )
    }

    private static func validateExistingLine(
        _ line: Int,
        in lines: [String]
    ) throws {
        let valid = validExistingLineRange(
            for: lines
        )

        guard let valid else {
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

    private static func validateExistingRange(
        _ range: LineRange,
        in lines: [String]
    ) throws {
        let valid = validExistingLineRange(
            for: lines
        )

        guard let valid else {
            throw StandardEditError.lineRangeOutOfBounds(
                range,
                valid: nil
            )
        }

        guard valid.contains(range.start),
              valid.contains(range.end),
              range.start <= range.end else {
            throw StandardEditError.lineRangeOutOfBounds(
                range,
                valid: valid
            )
        }
    }

    private static func validateInsertionLine(
        _ line: Int,
        in lines: [String]
    ) throws {
        let valid = validInsertionLineRange(
            for: lines
        )

        guard valid.contains(line) else {
            throw StandardEditError.insertionLineOutOfBounds(
                line,
                valid: valid
            )
        }
    }

    private static func validateInsertionSite(
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

    private static func validExistingLineRange(
        for lines: [String]
    ) -> ClosedRange<Int>? {
        guard !lines.isEmpty else {
            return nil
        }

        return 1...lines.count
    }

    private static func validInsertionLineRange(
        for lines: [String]
    ) -> ClosedRange<Int> {
        1...max(
            1,
            lines.count + 1
        )
    }
}
