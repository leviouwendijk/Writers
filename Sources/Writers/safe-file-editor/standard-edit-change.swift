import Foundation
import Position

public enum StandardEditChangeKind: String, Codable, Sendable, Hashable, CaseIterable {
    case insertion
    case deletion
    case replacement
}

public struct StandardEditChange: Codable, Sendable, Hashable {
    public let kind: StandardEditChangeKind
    public let originalLineRange: LineRange?
    public let editedLineRange: LineRange?
    public let originalLines: [String]
    public let editedLines: [String]
    public let originalFingerprint: StandardContentFingerprint?
    public let editedFingerprint: StandardContentFingerprint?
    public let originalAnchor: StandardEditAnchor?
    public let editedAnchor: StandardEditAnchor?

    public init(
        kind: StandardEditChangeKind,
        originalLineRange: LineRange?,
        editedLineRange: LineRange?,
        originalLines: [String],
        editedLines: [String],
        originalFingerprint: StandardContentFingerprint?,
        editedFingerprint: StandardContentFingerprint?,
        originalAnchor: StandardEditAnchor?,
        editedAnchor: StandardEditAnchor?
    ) {
        self.kind = kind
        self.originalLineRange = originalLineRange
        self.editedLineRange = editedLineRange
        self.originalLines = originalLines
        self.editedLines = editedLines
        self.originalFingerprint = originalFingerprint
        self.editedFingerprint = editedFingerprint
        self.originalAnchor = originalAnchor
        self.editedAnchor = editedAnchor
    }

    public var hasOriginalLines: Bool {
        !originalLines.isEmpty
    }

    public var hasEditedLines: Bool {
        !editedLines.isEmpty
    }

    public var rollbackOperation: StandardEditOperation? {
        switch kind {
        case .insertion:
            guard let editedLineRange else {
                return nil
            }

            return StandardEditOperation.deleteLines(
                editedLineRange
            )

        case .deletion:
            guard let originalLineRange else {
                return nil
            }

            return StandardEditOperation.insertLines(
                originalLines,
                atLine: originalLineRange.start
            )

        case .replacement:
            guard let editedLineRange else {
                return nil
            }

            return StandardEditOperation.replaceLines(
                editedLineRange,
                with: originalLines
            )
        }
    }
}
