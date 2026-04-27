import Foundation

public enum StandardMutationRollbackActionKind: String, Sendable, Codable, Hashable, CaseIterable {
    case none
    case delete_created_file
    case restore_text
    case restore_data
}

public enum StandardMutationRollbackAction: Sendable {
    case none
    case delete_created_file(StandardMutationDeleteCreatedFile)
    case restore_text(StandardMutationRestoreText)
    case restore_data(StandardMutationRestoreData)

    public var kind: StandardMutationRollbackActionKind {
        switch self {
        case .none:
            return .none

        case .delete_created_file:
            return .delete_created_file

        case .restore_text:
            return .restore_text

        case .restore_data:
            return .restore_data
        }
    }

    public var target: URL? {
        switch self {
        case .none:
            return nil

        case .delete_created_file(let action):
            return action.target

        case .restore_text(let action):
            return action.target

        case .restore_data(let action):
            return action.target
        }
    }

    public var targetPath: String? {
        target?.path
    }
}

public struct StandardMutationDeleteCreatedFile: Sendable {
    public let target: URL
    public let requiredCurrentFingerprint: StandardContentFingerprint

    public init(
        target: URL,
        requiredCurrentFingerprint: StandardContentFingerprint
    ) {
        self.target = target.standardizedFileURL
        self.requiredCurrentFingerprint = requiredCurrentFingerprint
    }
}

public struct StandardMutationRestoreText: Sendable {
    public let target: URL
    public let content: String
    public let encoding: String.Encoding
    public let requiredCurrentFingerprint: StandardContentFingerprint?

    public init(
        target: URL,
        content: String,
        encoding: String.Encoding = .utf8,
        requiredCurrentFingerprint: StandardContentFingerprint?
    ) {
        self.target = target.standardizedFileURL
        self.content = content
        self.encoding = encoding
        self.requiredCurrentFingerprint = requiredCurrentFingerprint
    }
}

public struct StandardMutationRestoreData: Sendable {
    public let target: URL
    public let content: Data
    public let requiredCurrentFingerprint: StandardContentFingerprint?

    public init(
        target: URL,
        content: Data,
        requiredCurrentFingerprint: StandardContentFingerprint?
    ) {
        self.target = target.standardizedFileURL
        self.content = content
        self.requiredCurrentFingerprint = requiredCurrentFingerprint
    }
}

public struct StandardMutationRollbackReport: Sendable, Codable, Hashable {
    public let actionCount: Int
    public let targetCount: Int

    public init(
        actionCount: Int,
        targetCount: Int
    ) {
        self.actionCount = actionCount
        self.targetCount = targetCount
    }
}

public struct StandardMutationRollbackPlan: Sendable {
    public let id: UUID
    public let source: UUID
    public let actions: [StandardMutationRollbackAction]
    public let report: StandardMutationRollbackReport

    public init(
        id: UUID = .init(),
        source: UUID,
        actions: [StandardMutationRollbackAction]
    ) {
        self.id = id
        self.source = source
        self.actions = actions
        self.report = .init(
            actionCount: actions.count,
            targetCount: Set(
                actions.compactMap(\.targetPath)
            ).count
        )
    }
}

public typealias StandardRollbackActionKind = StandardMutationRollbackActionKind
public typealias StandardRollbackAction = StandardMutationRollbackAction
public typealias StandardDeleteCreatedFile = StandardMutationDeleteCreatedFile
public typealias StandardRestoreText = StandardMutationRestoreText
public typealias StandardRestoreData = StandardMutationRestoreData
public typealias StandardRollbackReport = StandardMutationRollbackReport
public typealias StandardRollbackPlan = StandardMutationRollbackPlan
