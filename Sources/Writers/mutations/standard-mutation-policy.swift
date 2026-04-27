public enum StandardCreatePolicy: String, Sendable, Codable, Hashable, CaseIterable {
    case missing
    // case overwrite
}

public enum StandardReplacePolicy: String, Sendable, Codable, Hashable, CaseIterable {
    case existing
    case create
    case upsert
}

public enum StandardDeletePolicy: String, Sendable, Codable, Hashable, CaseIterable {
    case existing
    case missing_ok
}

public enum StandardMutationFailurePolicy: String, Sendable, Codable, Hashable, CaseIterable {
    case stop
    case rollback_applied
}
