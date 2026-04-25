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

        case .insertLines(let insertedLines, let line):
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

        case .replaceLines(let range, let replacementLines):
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
        }
    }

    static func applying(
        _ operations: [Self],
        to content: String
    ) throws -> String {
        try operations.reduce(
            content
        ) { partial, operation in
            try operation.applying(
                to: partial
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
