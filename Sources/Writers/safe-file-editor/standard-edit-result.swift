import Foundation
import Difference
import Position

public struct StandardEditResult: Sendable {
    public let target: URL
    public let operations: [StandardEditOperation]
    public let originalContent: String
    public let editedContent: String
    public let difference: SafeFileDifference
    public let changes: [StandardEditChange]
    public let writeResult: SafeWriteResult?

    public init(
        target: URL,
        operations: [StandardEditOperation],
        originalContent: String,
        editedContent: String,
        difference: SafeFileDifference,
        changes: [StandardEditChange],
        writeResult: SafeWriteResult?
    ) {
        self.target = target
        self.operations = operations
        self.originalContent = originalContent
        self.editedContent = editedContent
        self.difference = difference
        self.changes = changes
        self.writeResult = writeResult
    }

    public var hasChanges: Bool {
        difference.hasChanges
    }

    public var performedWrite: Bool {
        writeResult != nil
    }

    public var insertions: Int {
        difference.insertions
    }

    public var deletions: Int {
        difference.deletions
    }

    public var changeCount: Int {
        difference.changeCount
    }

    public var originalFingerprint: StandardContentFingerprint {
        StandardContentFingerprint.fingerprint(
            for: originalContent
        )
    }

    public var editedFingerprint: StandardContentFingerprint {
        StandardContentFingerprint.fingerprint(
            for: editedContent
        )
    }

    public var baseSnapshot: StandardEditSnapshot {
        .init(
            content: originalContent
        )
    }

    public var editedSnapshot: StandardEditSnapshot {
        .init(
            content: editedContent
        )
    }

    public var originalChangedLineRanges: [LineRange] {
        changes.compactMap(\.originalLineRange)
    }

    public var editedChangedLineRanges: [LineRange] {
        changes.compactMap(\.editedLineRange)
    }

    public var rollbackOperations: [StandardEditOperation] {
        changes
            .reversed()
            .compactMap(\.rollbackOperation)
    }

    public func diffLayout(
        options: SafeFileDiffRenderOptions = .unified
    ) -> SafeFileDiffLayout {
        DifferenceRenderer.layout(
            difference,
            options: options
        )
    }

    public func renderedDifference(
        options: SafeFileDiffRenderOptions = .unified
    ) -> String {
        DifferenceRenderer.render(
            difference,
            options: options
        )
    }

    public func renderedDifference<Renderer: DifferenceRendering>(
        using renderer: Renderer.Type
    ) -> String {
        Renderer.render(difference)
    }

    public func originalChangedSpans(
        file: String? = nil
    ) -> [PositionSpan] {
        makeLineSpans(
            for: originalChangedLineRanges,
            in: originalContent,
            file: file ?? target.path
        )
    }

    public func editedChangedSpans(
        file: String? = nil
    ) -> [PositionSpan] {
        makeLineSpans(
            for: editedChangedLineRanges,
            in: editedContent,
            file: file ?? target.path
        )
    }

    public func originalChangedSlices() -> [FileLineSlice] {
        makeLineSlices(
            for: originalChangedLineRanges,
            in: originalContent
        )
    }

    public func editedChangedSlices() -> [FileLineSlice] {
        makeLineSlices(
            for: editedChangedLineRanges,
            in: editedContent
        )
    }

    public func record(
        id: UUID = .init(),
        createdAt: Date = .init()
    ) -> StandardEditRecord {
        .init(
            id: id,
            target: target,
            createdAt: createdAt,
            base: baseSnapshot,
            edited: editedSnapshot,
            operations: operations,
            changes: changes
        )
    }

    private func makeLineSpans(
        for ranges: [LineRange],
        in text: String,
        file: String?
    ) -> [PositionSpan] {
        let lineTable = LineTable(text: text)

        return ranges.map { range in
            let startOffset = lineTable.lineStartOffset(
                forLine: range.start
            ) ?? 0

            let endOffset = lineTable.lineEndOffset(
                forLine: range.end
            ) ?? lineTable.length

            return lineTable.displaySpan(
                for: PositionRange(
                    uncheckedStart: .init(startOffset),
                    uncheckedEnd: .init(endOffset)
                ),
                file: file
            )
        }
    }

    private func makeLineSlices(
        for ranges: [LineRange],
        in text: String
    ) -> [FileLineSlice] {
        let lines = WriteTextLines(text).lines

        return ranges.map { range in
            let lowerBound = max(0, range.start - 1)
            let upperBound = min(lines.count, range.end)

            let sliceLines: [String]
            if lowerBound < upperBound {
                sliceLines = Array(lines[lowerBound..<upperBound])
            } else {
                sliceLines = []
            }

            return .init(
                file: target,
                startLine: range.start,
                lines: sliceLines
            )
        }
    }
}
