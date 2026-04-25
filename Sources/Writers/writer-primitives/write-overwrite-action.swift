public enum WriteOverwriteAction: String, Codable, Sendable, Hashable, CaseIterable {
    case create
    case overwrite_blank
    case overwrite_nonblank
    case abort_collision
    case unchanged
}

public extension WriteOverwriteAction {
    var canProceed: Bool {
        self != .abort_collision
    }

    var writesOverExistingContent: Bool {
        switch self {
        case .overwrite_blank,
             .overwrite_nonblank,
             .unchanged:
            return true

        case .create,
             .abort_collision:
            return false
        }
    }

    var requiresBackupDecision: Bool {
        self == .overwrite_nonblank
    }
}
