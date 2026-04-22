public enum StandardEditMergeStrategy: Sendable, Hashable {
    case alreadyApplied
    case replaceFromBase
    case replayAnchors
    case threeWayMerge
}
