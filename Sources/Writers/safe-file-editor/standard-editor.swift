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
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try preview(
            [
                operation,
            ],
            mode: mode,
            encoding: encoding
        )
    }

    public func preview(
        _ operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        let original = try IntegratedReader.text(
            at: url,
            encoding: encoding,
            missingFileReturnsEmpty: true,
            normalizeNewlines: false
        )

        let edited = try StandardEditOperation.applying(
            operations,
            to: original,
            mode: mode
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
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> StandardEditResult {
        try edit(
            [
                operation,
            ],
            mode: mode,
            encoding: encoding,
            options: options
        )
    }

    @discardableResult
    public func edit(
        _ operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> StandardEditResult {
        let preview = try preview(
            operations,
            mode: mode,
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

    internal func makeResult(
        operations: [StandardEditOperation],
        original: String,
        edited: String,
        writeResult: SafeWriteResult?
    ) -> StandardEditResult {
        let difference = WriteDifference.lines(
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

    internal func changes(
        for difference: SafeFileDifference,
        originalContent: String,
        editedContent: String
    ) -> [StandardEditChange] {
        let originalSnapshotLines = WriteTextLines(
            originalContent
        ).lines

        let editedSnapshotLines = WriteTextLines(
            editedContent
        ).lines

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
