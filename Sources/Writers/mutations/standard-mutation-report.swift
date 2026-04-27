import Foundation

public enum StandardMutationWarning: String, Sendable, Codable, Hashable, CaseIterable {
    case no_changes
    case delete_missing_ok
    case binary_resource
}

public struct StandardPlannedMutationReport: Sendable, Codable, Hashable {
    public let id: UUID
    public let index: Int
    public let target: URL
    public let resource: WriteResourceChangeKind
    public let delta: WriteDeltaKind
    public let warningCodes: [StandardMutationWarning]

    public init(
        id: UUID,
        index: Int,
        target: URL,
        resource: WriteResourceChangeKind,
        delta: WriteDeltaKind,
        warningCodes: [StandardMutationWarning] = []
    ) {
        self.id = id
        self.index = index
        self.target = target.standardizedFileURL
        self.resource = resource
        self.delta = delta
        self.warningCodes = warningCodes
    }
}

public struct StandardMutationReport: Sendable, Codable, Hashable {
    public let id: UUID
    public let entryCount: Int
    public let targetCount: Int
    public let creates: Int
    public let updates: Int
    public let deletes: Int
    public let unchanged: Int
    public let entries: [StandardPlannedMutationReport]

    public init(
        id: UUID,
        entries: [StandardPlannedMutation]
    ) {
        self.id = id
        self.entryCount = entries.count
        self.targetCount = Set(
            entries.map {
                $0.target.path
            }
        ).count
        self.creates = entries.filter {
            $0.resource == .creation
        }.count
        self.updates = entries.filter {
            $0.resource == .update
        }.count
        self.deletes = entries.filter {
            $0.resource == .deletion
        }.count
        self.unchanged = entries.filter {
            $0.delta == .unchanged
        }.count
        self.entries = entries.map(\.report)
    }
}
