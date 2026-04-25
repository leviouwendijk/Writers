import Foundation

public struct StandardEditMerger: Sendable {
    private struct AnchorLocation: Sendable, Hashable {
        let startIndex: Int
        let removedCount: Int

        var endIndex: Int {
            startIndex + removedCount
        }
    }

    private struct MergeHunk: Sendable, Hashable {
        let startIndex: Int
        let removedCount: Int
        let replacementLines: [String]

        var endIndex: Int {
            startIndex + removedCount
        }
    }

    public let record: StandardEditRecord
    public let writer: StandardWriter

    public var url: URL {
        writer.url
    }

    public init(
        record: StandardEditRecord
    ) {
        self.record = record
        self.writer = .init(record.target)
    }

    public init(
        record: StandardEditRecord,
        writer: StandardWriter
    ) {
        self.record = record
        self.writer = writer
    }

    public func preview(
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditMergeResult {
        let current = try IntegratedReader.text(
            at: url,
            encoding: encoding,
            missingFileReturnsEmpty: true,
            normalizeNewlines: false
        )

        return try preview(
            currentContent: current
        )
    }

    public func preview(
        currentContent: String
    ) throws -> StandardEditMergeResult {
        let strategy: StandardEditMergeStrategy
        let mergedContent: String

        if record.matchesEditedContent(currentContent) {
            strategy = .alreadyApplied
            mergedContent = currentContent
        } else if record.matchesOriginalContent(currentContent) {
            strategy = .replaceFromBase
            mergedContent = record.edited.content
        } else if let replayed = try? replayAnchors(
            into: currentContent
        ) {
            strategy = .replayAnchors
            mergedContent = replayed
        } else {
            strategy = .threeWayMerge
            mergedContent = try threeWayMerge(
                currentContent: currentContent
            )
        }

        return .init(
            target: url,
            strategy: strategy,
            currentContent: currentContent,
            mergedContent: mergedContent,
            difference: WriteDifference.lines(
                old: currentContent,
                new: mergedContent,
                oldName: "\(url.lastPathComponent) (current)",
                newName: "\(url.lastPathComponent) (merged)"
            ),
            writeResult: nil
        )
    }

    @discardableResult
    public func merge(
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> StandardEditMergeResult {
        let preview = try preview(
            encoding: encoding
        )

        guard preview.hasChanges else {
            return preview
        }

        let writeResult = try writer.write(
            preview.mergedContent,
            encoding: encoding,
            options: options
        )

        return .init(
            target: preview.target,
            strategy: preview.strategy,
            currentContent: preview.currentContent,
            mergedContent: preview.mergedContent,
            difference: preview.difference,
            writeResult: writeResult
        )
    }

    private func currentString(
        encoding: String.Encoding
    ) throws -> String {
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return ""
        }

        do {
            return try String(
                contentsOf: url,
                encoding: encoding
            )
        } catch {
            throw SafeFileError.io(
                underlying: error
            )
        }
    }

    private func replayAnchors(
        into currentContent: String
    ) throws -> String {
        var lines = WriteTextLines(
            currentContent
        ).lines

        for (offset, change) in record.changes.enumerated() {
            let changeIndex = offset + 1
            let location = try locateForwardChange(
                change,
                in: lines,
                changeIndex: changeIndex
            )

            applyForwardChange(
                change,
                at: location,
                to: &lines
            )
        }

        return makeContent(
            from: lines
        )
    }

    private func locateForwardChange(
        _ change: StandardEditChange,
        in lines: [String],
        changeIndex: Int
    ) throws -> AnchorLocation {
        switch change.kind {
        case .insertion:
            let candidates = findInsertionCandidates(
                anchor: change.originalAnchor,
                in: lines
            )

            if candidates.isEmpty {
                throw StandardEditMergeError.anchorMatchNotFound(
                    changeIndex: changeIndex
                )
            }

            guard candidates.count == 1 else {
                throw StandardEditMergeError.ambiguousAnchorMatch(
                    changeIndex: changeIndex,
                    candidateCount: candidates.count
                )
            }

            return candidates[0]

        case .deletion, .replacement:
            let candidates = findReplacementCandidates(
                targetLines: change.originalLines,
                anchor: change.originalAnchor,
                in: lines
            )

            if candidates.isEmpty {
                throw StandardEditMergeError.anchorMatchNotFound(
                    changeIndex: changeIndex
                )
            }

            guard candidates.count == 1 else {
                throw StandardEditMergeError.ambiguousAnchorMatch(
                    changeIndex: changeIndex,
                    candidateCount: candidates.count
                )
            }

            return candidates[0]
        }
    }

    private func findInsertionCandidates(
        anchor: StandardEditAnchor?,
        in lines: [String]
    ) -> [AnchorLocation] {
        var out: [AnchorLocation] = []

        for index in 0...lines.count {
            if anchorMatchesInsertionSite(
                anchor,
                at: index,
                in: lines
            ) {
                out.append(
                    .init(
                        startIndex: index,
                        removedCount: 0
                    )
                )
            }
        }

        return out
    }

    private func findReplacementCandidates(
        targetLines: [String],
        anchor: StandardEditAnchor?,
        in lines: [String]
    ) -> [AnchorLocation] {
        guard !targetLines.isEmpty else {
            return []
        }

        guard targetLines.count <= lines.count else {
            return []
        }

        var out: [AnchorLocation] = []

        for startIndex in 0...(lines.count - targetLines.count) {
            let endIndex = startIndex + targetLines.count
            let candidate = Array(lines[startIndex..<endIndex])

            guard candidate == targetLines else {
                continue
            }

            if anchorMatchesRange(
                anchor,
                startIndex: startIndex,
                endIndex: endIndex,
                in: lines
            ) {
                out.append(
                    .init(
                        startIndex: startIndex,
                        removedCount: targetLines.count
                    )
                )
            }
        }

        return out
    }

    private func anchorMatchesInsertionSite(
        _ anchor: StandardEditAnchor?,
        at index: Int,
        in lines: [String]
    ) -> Bool {
        guard let anchor else {
            return true
        }

        if !anchor.beforeLines.isEmpty {
            guard index >= anchor.beforeLines.count else {
                return false
            }

            let lowerBound = index - anchor.beforeLines.count
            let upperBound = index
            let slice = Array(lines[lowerBound..<upperBound])

            guard slice == anchor.beforeLines else {
                return false
            }
        }

        if !anchor.afterLines.isEmpty {
            guard index + anchor.afterLines.count <= lines.count else {
                return false
            }

            let lowerBound = index
            let upperBound = index + anchor.afterLines.count
            let slice = Array(lines[lowerBound..<upperBound])

            guard slice == anchor.afterLines else {
                return false
            }
        }

        return true
    }

    private func anchorMatchesRange(
        _ anchor: StandardEditAnchor?,
        startIndex: Int,
        endIndex: Int,
        in lines: [String]
    ) -> Bool {
        guard let anchor else {
            return true
        }

        if !anchor.beforeLines.isEmpty {
            guard startIndex >= anchor.beforeLines.count else {
                return false
            }

            let lowerBound = startIndex - anchor.beforeLines.count
            let upperBound = startIndex
            let slice = Array(lines[lowerBound..<upperBound])

            guard slice == anchor.beforeLines else {
                return false
            }
        }

        if !anchor.afterLines.isEmpty {
            guard endIndex + anchor.afterLines.count <= lines.count else {
                return false
            }

            let lowerBound = endIndex
            let upperBound = endIndex + anchor.afterLines.count
            let slice = Array(lines[lowerBound..<upperBound])

            guard slice == anchor.afterLines else {
                return false
            }
        }

        return true
    }

    private func applyForwardChange(
        _ change: StandardEditChange,
        at location: AnchorLocation,
        to lines: inout [String]
    ) {
        switch change.kind {
        case .insertion:
            lines.insert(
                contentsOf: change.editedLines,
                at: location.startIndex
            )

        case .deletion:
            lines.removeSubrange(
                location.startIndex..<location.endIndex
            )

        case .replacement:
            lines.replaceSubrange(
                location.startIndex..<location.endIndex,
                with: change.editedLines
            )
        }
    }

    private func threeWayMerge(
        currentContent: String
    ) throws -> String {
        let baseLines = WriteTextLines(
            record.base.content
        ).lines

        let editedHunks = diffHunks(
            baseContent: record.base.content,
            otherContent: record.edited.content
        )

        let currentHunks = diffHunks(
            baseContent: record.base.content,
            otherContent: currentContent
        )

        let mergedLines = try mergeHunks(
            baseLines: baseLines,
            editedHunks: editedHunks,
            currentHunks: currentHunks
        )

        return makeContent(
            from: mergedLines
        )
    }

    private func diffHunks(
        baseContent: String,
        otherContent: String
    ) -> [MergeHunk] {
        let difference = WriteDifference.lines(
            old: baseContent,
            new: otherContent,
            oldName: "base",
            newName: "other"
        )

        var out: [MergeHunk] = []

        var baseLine = 1
        var otherLine = 1

        var currentBaseStart: Int?
        var currentBaseSiteLine: Int?
        var currentRemovedLines: [String] = []
        var currentAddedLines: [String] = []

        func flush() {
            guard
                !currentRemovedLines.isEmpty
                || !currentAddedLines.isEmpty
            else {
                return
            }

            let startLine = currentBaseStart
                ?? currentBaseSiteLine
                ?? baseLine

            out.append(
                .init(
                    startIndex: max(0, startLine - 1),
                    removedCount: currentRemovedLines.count,
                    replacementLines: currentAddedLines
                )
            )

            currentBaseStart = nil
            currentBaseSiteLine = nil
            currentRemovedLines = []
            currentAddedLines = []
        }

        for line in difference.lines {
            switch line.operation {
            case .equal:
                flush()
                baseLine += 1
                otherLine += 1

            case .delete:
                if currentBaseStart == nil {
                    currentBaseStart = baseLine
                }

                if currentBaseSiteLine == nil {
                    currentBaseSiteLine = baseLine
                }

                currentRemovedLines.append(line.text)
                baseLine += 1

            case .insert:
                if currentBaseSiteLine == nil {
                    currentBaseSiteLine = baseLine
                }

                currentAddedLines.append(line.text)
                otherLine += 1
            }
        }

        flush()

        return out
    }

    private func mergeHunks(
        baseLines: [String],
        editedHunks: [MergeHunk],
        currentHunks: [MergeHunk]
    ) throws -> [String] {
        var result: [String] = []

        var cursor = 0
        var editedIndex = 0
        var currentIndex = 0

        func emitBase(
            upTo limit: Int
        ) {
            guard cursor < limit else {
                return
            }

            result.append(
                contentsOf: baseLines[cursor..<limit]
            )
            cursor = limit
        }

        func emit(
            _ hunk: MergeHunk
        ) {
            emitBase(
                upTo: hunk.startIndex
            )
            result.append(
                contentsOf: hunk.replacementLines
            )
            cursor = hunk.endIndex
        }

        while editedIndex < editedHunks.count || currentIndex < currentHunks.count {
            if editedIndex >= editedHunks.count {
                emit(
                    currentHunks[currentIndex]
                )
                currentIndex += 1
                continue
            }

            if currentIndex >= currentHunks.count {
                emit(
                    editedHunks[editedIndex]
                )
                editedIndex += 1
                continue
            }

            let edited = editedHunks[editedIndex]
            let current = currentHunks[currentIndex]

            if strictlyBefore(
                edited,
                current
            ) {
                emit(edited)
                editedIndex += 1
                continue
            }

            if strictlyBefore(
                current,
                edited
            ) {
                emit(current)
                currentIndex += 1
                continue
            }

            var groupStart = min(
                edited.startIndex,
                current.startIndex
            )
            var groupEnd = max(
                edited.endIndex,
                current.endIndex
            )

            var editedGroup: [MergeHunk] = []
            var currentGroup: [MergeHunk] = []

            repeat {
                var advanced = false

                while editedIndex < editedHunks.count,
                      editedHunks[editedIndex].startIndex < groupEnd {
                    let hunk = editedHunks[editedIndex]
                    editedGroup.append(hunk)
                    groupStart = min(groupStart, hunk.startIndex)
                    groupEnd = max(groupEnd, hunk.endIndex)
                    editedIndex += 1
                    advanced = true
                }

                while currentIndex < currentHunks.count,
                      currentHunks[currentIndex].startIndex < groupEnd {
                    let hunk = currentHunks[currentIndex]
                    currentGroup.append(hunk)
                    groupStart = min(groupStart, hunk.startIndex)
                    groupEnd = max(groupEnd, hunk.endIndex)
                    currentIndex += 1
                    advanced = true
                }

                if !advanced {
                    break
                }
            } while true

            if editedGroup.isEmpty {
                editedGroup.append(edited)
                editedIndex += 1
            }

            if currentGroup.isEmpty {
                currentGroup.append(current)
                currentIndex += 1
            }

            emitBase(
                upTo: groupStart
            )

            let baseSegment = Array(
                baseLines[groupStart..<groupEnd]
            )

            let editedSegment = render(
                hunks: editedGroup,
                over: baseLines,
                in: groupStart..<groupEnd
            )

            let currentSegment = render(
                hunks: currentGroup,
                over: baseLines,
                in: groupStart..<groupEnd
            )

            if editedSegment == currentSegment {
                result.append(
                    contentsOf: editedSegment
                )
            } else if editedSegment == baseSegment {
                result.append(
                    contentsOf: currentSegment
                )
            } else if currentSegment == baseSegment {
                result.append(
                    contentsOf: editedSegment
                )
            } else {
                throw StandardEditMergeError.threeWayConflict(
                    baseStartLine: groupStart + 1,
                    baseEndLine: max(groupStart + 1, groupEnd)
                )
            }

            cursor = groupEnd
        }

        emitBase(
            upTo: baseLines.count
        )

        return result
    }

    private func strictlyBefore(
        _ lhs: MergeHunk,
        _ rhs: MergeHunk
    ) -> Bool {
        if lhs.endIndex < rhs.startIndex {
            return true
        }

        if lhs.endIndex > rhs.startIndex {
            return false
        }

        return !(lhs.removedCount == 0
                 && rhs.removedCount == 0
                 && lhs.startIndex == rhs.startIndex)
    }

    private func render(
        hunks: [MergeHunk],
        over baseLines: [String],
        in range: Range<Int>
    ) -> [String] {
        var result: [String] = []
        var cursor = range.lowerBound

        for hunk in hunks.sorted(by: hunkSort) {
            if cursor < hunk.startIndex {
                result.append(
                    contentsOf: baseLines[cursor..<hunk.startIndex]
                )
            }

            result.append(
                contentsOf: hunk.replacementLines
            )

            cursor = hunk.endIndex
        }

        if cursor < range.upperBound {
            result.append(
                contentsOf: baseLines[cursor..<range.upperBound]
            )
        }

        return result
    }

    private func hunkSort(
        _ lhs: MergeHunk,
        _ rhs: MergeHunk
    ) -> Bool {
        if lhs.startIndex != rhs.startIndex {
            return lhs.startIndex < rhs.startIndex
        }

        return lhs.removedCount < rhs.removedCount
    }

    private func makeContent(
        from lines: [String]
    ) -> String {
        guard !lines.isEmpty else {
            return ""
        }

        return lines.joined(separator: "\n")
    }
}
