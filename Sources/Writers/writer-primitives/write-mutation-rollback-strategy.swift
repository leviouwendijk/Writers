public enum WriteMutationRollbackStrategy: String, Codable, Sendable, Hashable, CaseIterable {
    case before_snapshot
    case rollback_operations
    case backup_record
}
