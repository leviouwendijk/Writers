import Foundation

public struct StandardEditRecord: Codable, Sendable, Hashable {
    public let id: UUID
    public let target: URL
    public let createdAt: Date
    public let base: StandardEditSnapshot
    public let edited: StandardEditSnapshot
    public let operations: [StandardEditOperation]
    public let changes: [StandardEditChange]

    public init(
        id: UUID,
        target: URL,
        createdAt: Date,
        base: StandardEditSnapshot,
        edited: StandardEditSnapshot,
        operations: [StandardEditOperation],
        changes: [StandardEditChange]
    ) {
        self.id = id
        self.target = target
        self.createdAt = createdAt
        self.base = base
        self.edited = edited
        self.operations = operations
        self.changes = changes
    }

    public var originalFingerprint: StandardContentFingerprint {
        base.fingerprint
    }

    public var editedFingerprint: StandardContentFingerprint {
        edited.fingerprint
    }

    public var rollbackOperations: [StandardEditOperation] {
        changes
            .reversed()
            .compactMap(\.rollbackOperation)
    }

    public func matchesOriginalContent(
        _ content: String
    ) -> Bool {
        StandardContentFingerprint.fingerprint(
            for: content
        ) == base.fingerprint
    }

    public func matchesEditedContent(
        _ content: String
    ) -> Bool {
        StandardContentFingerprint.fingerprint(
            for: content
        ) == edited.fingerprint
    }

    public func canApplyForward(
        to currentContent: String
    ) -> Bool {
        matchesOriginalContent(currentContent)
    }

    public func canRollback(
        from currentContent: String
    ) -> Bool {
        matchesEditedContent(currentContent)
    }
}
