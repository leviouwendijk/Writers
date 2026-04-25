public enum WriteDeltaKind: String, Codable, Sendable, Hashable, CaseIterable {
    case addition
    case deletion
    case replacement
    case mixed
    case unchanged
    case unknown
}
