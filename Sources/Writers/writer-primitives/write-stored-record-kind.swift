public enum WriteStoredRecordKind: String, Codable, Sendable, Hashable, CaseIterable {
    case mutation
    case edit
    case unknown
}
