import Foundation
import Position

public typealias SafeFileEditor = StandardEditor

public struct StandardEditor: Sendable {
    private static let anchorContextLineCount: Int = 3

    public let writer: StandardWriter

    public var url: URL {
        writer.url
    }

    public init(
        writer: StandardWriter
    ) {
        self.writer = writer
    }

    public init(
        _ url: URL
    ) {
        self.writer = .init(url)
    }

    public func preview(
        _ operation: StandardEditOperation,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try preview(
            [operation],
            encoding: encoding
        )
    }

    public func preview(
        _ operations: [StandardEditOperation],
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        let original = try standardReadText(
            at: url,
            encoding: encoding,
            missingFileReturnsEmpty: true,
            normalizeNewlines: false
        )

        let edited = try apply(
            operations,
            to: original
        )

        return makeResult(
            operations: operations,
            original: original,
            edited: edited,
            writeResult: nil
        )
    }

    @discardableResult
    public func edit(
        _ operation: StandardEditOperation,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> StandardEditResult {
        try edit(
            [operation],
            encoding: encoding,
            options: options
        )
    }

    @discardableResult
    public func edit(
        _ operations: [StandardEditOperation],
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> StandardEditResult {
        let preview = try preview(
            operations,
            encoding: encoding
        )

        guard preview.hasChanges else {
            return preview
        }

        let writeResult = try writer.write(
            preview.editedContent,
            encoding: encoding,
            options: options
        )

        return .init(
            target: preview.target,
            operations: preview.operations,
            originalContent: preview.originalContent,
            editedContent: preview.editedContent,
            difference: preview.difference,
            changes: preview.changes,
            writeResult: writeResult
        )
    }

    // private func currentString(
    //     encoding: String.Encoding
    // ) throws -> String {
    // }

    private func makeResult(
        operations: [StandardEditOperation],
        original: String,
        edited: String,
        writeResult: SafeWriteResult?
    ) -> StandardEditResult {
        let difference = makeStructuredLineDiff(
            old: original,
            new: edited,
            oldName: "\(url.lastPathComponent) (existing)",
            newName: "\(url.lastPathComponent) (edited)"
        )

        return .init(
            target: url,
            operations: operations,
            originalContent: original,
            editedContent: edited,
            difference: difference,
            changes: changes(
                for: difference,
                originalContent: original,
                editedContent: edited
            ),
            writeResult: writeResult
        )
    }

    private func apply(
        _ operations: [StandardEditOperation],
        to content: String
    ) throws -> String {
        try operations.reduce(
            content
        ) { partial, operation in
            try apply(
                operation,
                to: partial
            )
        }
    }

    private func apply(
        _ operation: StandardEditOperation,
        to content: String
    ) throws -> String {
        switch operation {
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
            let needle = try validatedNeedle(
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
            let needle = try validatedNeedle(
                needle
            )

            let count = occurrenceCount(
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
            let needle = try validatedNeedle(
                needle
            )

            let count = occurrenceCount(
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
            var lines = editableLines(
                from: content
            )

            try validateExistingLine(
                line,
                in: lines
            )

            lines[line - 1] = replacement
            return makeContent(from: lines)

        case .insertLines(let insertedLines, let line):
            var lines = editableLines(
                from: content
            )

            try validateInsertionLine(
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

            return makeContent(from: lines)

        case .replaceLines(let range, let replacementLines):
            var lines = editableLines(
                from: content
            )

            try validateExistingRange(
                range,
                in: lines
            )

            lines.replaceSubrange(
                (range.start - 1)..<range.end,
                with: replacementLines
            )

            return makeContent(from: lines)

        case .deleteLines(let range):
            var lines = editableLines(
                from: content
            )

            try validateExistingRange(
                range,
                in: lines
            )

            lines.removeSubrange(
                (range.start - 1)..<range.end
            )

            return makeContent(from: lines)
        }
    }

    private func validatedNeedle(
        _ needle: String
    ) throws -> String {
        guard !needle.isEmpty else {
            throw StandardEditError.emptyMatchString
        }

        return needle
    }

    private func occurrenceCount(
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

    private func editableLines(
        from content: String
    ) -> [String] {
        guard !content.isEmpty else {
            return []
        }

        return content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .map(String.init)
    }

    private func makeContent(
        from lines: [String]
    ) -> String {
        guard !lines.isEmpty else {
            return ""
        }

        return lines.joined(separator: "\n")
    }

    private func validateExistingLine(
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

    private func validateExistingRange(
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
              valid.contains(range.end) else {
            throw StandardEditError.lineRangeOutOfBounds(
                range,
                valid: valid
            )
        }
    }

    private func validateInsertionLine(
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

    private func validExistingLineRange(
        for lines: [String]
    ) -> ClosedRange<Int>? {
        guard !lines.isEmpty else {
            return nil
        }

        return 1...lines.count
    }

    private func validInsertionLineRange(
        for lines: [String]
    ) -> ClosedRange<Int> {
        1...max(1, lines.count + 1)
    }

    private func changes(
        for difference: SafeFileDifference,
        originalContent: String,
        editedContent: String
    ) -> [StandardEditChange] {
        let originalSnapshotLines = editableLines(
            from: originalContent
        )
        let editedSnapshotLines = editableLines(
            from: editedContent
        )

        var out: [StandardEditChange] = []

        var originalLine = 1
        var editedLine = 1

        var currentOriginalStart: Int?
        var currentEditedStart: Int?

        var currentOriginalSiteLine: Int?
        var currentEditedSiteLine: Int?

        var currentOriginalLines: [String] = []
        var currentEditedLines: [String] = []

        func flush() {
            guard
                !currentOriginalLines.isEmpty
                || !currentEditedLines.isEmpty
            else {
                return
            }

            let originalRange: LineRange?
            if let start = currentOriginalStart,
               !currentOriginalLines.isEmpty {
                originalRange = .init(
                    uncheckedStart: start,
                    uncheckedEnd: start + currentOriginalLines.count - 1
                )
            } else {
                originalRange = nil
            }

            let editedRange: LineRange?
            if let start = currentEditedStart,
               !currentEditedLines.isEmpty {
                editedRange = .init(
                    uncheckedStart: start,
                    uncheckedEnd: start + currentEditedLines.count - 1
                )
            } else {
                editedRange = nil
            }

            let kind: StandardEditChangeKind
            if currentOriginalLines.isEmpty {
                kind = .insertion
            } else if currentEditedLines.isEmpty {
                kind = .deletion
            } else {
                kind = .replacement
            }

            out.append(
                .init(
                    kind: kind,
                    originalLineRange: originalRange,
                    editedLineRange: editedRange,
                    originalLines: currentOriginalLines,
                    editedLines: currentEditedLines,
                    originalFingerprint: StandardContentFingerprint.fingerprint(
                        forLines: currentOriginalLines
                    ),
                    editedFingerprint: StandardContentFingerprint.fingerprint(
                        forLines: currentEditedLines
                    ),
                    originalAnchor: makeAnchor(
                        in: originalSnapshotLines,
                        changedRange: originalRange,
                        siteLine: currentOriginalSiteLine
                    ),
                    editedAnchor: makeAnchor(
                        in: editedSnapshotLines,
                        changedRange: editedRange,
                        siteLine: currentEditedSiteLine
                    )
                )
            )

            currentOriginalStart = nil
            currentEditedStart = nil
            currentOriginalSiteLine = nil
            currentEditedSiteLine = nil
            currentOriginalLines = []
            currentEditedLines = []
        }

        for line in difference.lines {
            switch line.operation {
            case .equal:
                flush()
                originalLine += 1
                editedLine += 1

            case .delete:
                if currentOriginalStart == nil {
                    currentOriginalStart = originalLine
                }

                if currentOriginalSiteLine == nil {
                    currentOriginalSiteLine = originalLine
                }

                if currentEditedSiteLine == nil {
                    currentEditedSiteLine = editedLine
                }

                currentOriginalLines.append(line.text)
                originalLine += 1

            case .insert:
                if currentEditedStart == nil {
                    currentEditedStart = editedLine
                }

                if currentOriginalSiteLine == nil {
                    currentOriginalSiteLine = originalLine
                }

                if currentEditedSiteLine == nil {
                    currentEditedSiteLine = editedLine
                }

                currentEditedLines.append(line.text)
                editedLine += 1
            }
        }

        flush()

        return out
    }

    private func makeAnchor(
        in lines: [String],
        changedRange: LineRange?,
        siteLine: Int?
    ) -> StandardEditAnchor? {
        let context = Self.anchorContextLineCount

        let beforeBoundaryLine: Int
        let afterBoundaryLine: Int

        if let changedRange {
            beforeBoundaryLine = changedRange.start - 1
            afterBoundaryLine = changedRange.end + 1
        } else if let siteLine {
            beforeBoundaryLine = siteLine - 1
            afterBoundaryLine = siteLine
        } else {
            return nil
        }

        let beforeStartLine = max(
            1,
            beforeBoundaryLine - context + 1
        )
        let beforeEndLine = min(
            beforeBoundaryLine,
            lines.count
        )

        let beforeLines: [String]
        let normalizedBeforeStartLine: Int?

        if beforeStartLine <= beforeEndLine,
           beforeEndLine >= 1 {
            beforeLines = Array(
                lines[(beforeStartLine - 1)..<beforeEndLine]
            )
            normalizedBeforeStartLine = beforeStartLine
        } else {
            beforeLines = []
            normalizedBeforeStartLine = nil
        }

        let afterStartLine = max(
            1,
            afterBoundaryLine
        )
        let afterEndLine = min(
            lines.count,
            afterStartLine + context - 1
        )

        let afterLines: [String]
        let normalizedAfterStartLine: Int?

        if afterStartLine <= afterEndLine,
           afterStartLine <= lines.count {
            afterLines = Array(
                lines[(afterStartLine - 1)..<afterEndLine]
            )
            normalizedAfterStartLine = afterStartLine
        } else {
            afterLines = []
            normalizedAfterStartLine = nil
        }

        guard !beforeLines.isEmpty || !afterLines.isEmpty else {
            return nil
        }

        return .init(
            beforeLines: beforeLines,
            afterLines: afterLines,
            beforeFingerprint: StandardContentFingerprint.fingerprint(
                forLines: beforeLines
            ),
            afterFingerprint: StandardContentFingerprint.fingerprint(
                forLines: afterLines
            ),
            beforeStartLine: normalizedBeforeStartLine,
            afterStartLine: normalizedAfterStartLine
        )
    }
}
