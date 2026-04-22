import Foundation

public enum StandardEditMergeError: Error, LocalizedError {
    case anchorMatchNotFound(changeIndex: Int)
    case ambiguousAnchorMatch(changeIndex: Int, candidateCount: Int)
    case threeWayConflict(baseStartLine: Int, baseEndLine: Int)

    public var errorDescription: String? {
        switch self {
        case .anchorMatchNotFound(let changeIndex):
            return "Could not relocate edit change \(changeIndex) using its stored anchors."

        case .ambiguousAnchorMatch(let changeIndex, let candidateCount):
            return "Edit change \(changeIndex) matched \(candidateCount) possible locations; refusing to merge automatically."

        case .threeWayConflict(let baseStartLine, let baseEndLine):
            return "Three-way merge conflict in base lines \(baseStartLine)...\(baseEndLine)."
        }
    }
}
