public enum ExistingFilePolicy: String, Codable, Sendable, Hashable, CaseIterable {
    case abort
    case overwrite
}
