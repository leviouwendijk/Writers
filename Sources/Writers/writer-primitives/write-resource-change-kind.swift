public enum WriteResourceChangeKind: String, Codable, Sendable, Hashable, CaseIterable {
    case creation
    case update
    case deletion
    case unknown
}
