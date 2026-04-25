public enum WriteExecutionStalePlanPolicy: String, Codable, Sendable, Hashable, CaseIterable {
    case require_current_matches_plan
    case allow_drift
}
