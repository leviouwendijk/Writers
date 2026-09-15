import Foundation
import Readers

public enum StandardMutationEntry: Sendable, Codable, Hashable {
    case create_text(StandardCreateText)
    case replace_text(StandardReplaceText)
    case edit_text(StandardEditText)
    case copy(StandardCopyResource)
    case move(StandardMoveResource)
    case delete(StandardDeleteResource)

    public var target: URL {
        switch self {
        case .create_text(let entry):
            return entry.target

        case .replace_text(let entry):
            return entry.target

        case .edit_text(let entry):
            return entry.target

        case .copy(let entry):
            return entry.destination

        case .move(let entry):
            return entry.source

        case .delete(let entry):
            return entry.target
        }
    }

    public var targets: [URL] {
        switch self {
        case .copy(let entry):
            return [
                entry.source,
                entry.destination,
            ]

        case .move(let entry):
            return [
                entry.source,
                entry.destination,
            ]

        default:
            return [
                target,
            ]
        }
    }
}

public struct StandardCreateText: Sendable, Codable, Hashable {
    public var target: URL
    public var content: String
    public var policy: StandardCreatePolicy
    public var encoding: TextEncoding
    public var options: SafeWriteOptions

    public init(
        target: URL,
        content: String,
        policy: StandardCreatePolicy = .missing,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) {
        self.target = target.standardizedFileURL
        self.content = content
        self.policy = policy
        self.encoding = TextEncoding(encoding)
        self.options = options
    }
}

public struct StandardReplaceText: Sendable, Codable, Hashable {
    public var target: URL
    public var content: String
    public var policy: StandardReplacePolicy
    public var encoding: TextEncoding
    public var options: SafeWriteOptions

    public init(
        target: URL,
        content: String,
        policy: StandardReplacePolicy = .existing,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) {
        self.target = target.standardizedFileURL
        self.content = content
        self.policy = policy
        self.encoding = TextEncoding(encoding)
        self.options = options
    }
}

public struct StandardEditText: Sendable, Codable, Hashable {
    public var target: URL
    public var operations: [StandardEditOperation]
    public var mode: StandardEditMode
    public var constraint: StandardEditConstraint
    public var options: StandardEditApplyOptions

    public init(
        target: URL,
        operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        constraint: StandardEditConstraint = .unrestricted,
        options: StandardEditApplyOptions = .init()
    ) {
        self.target = target.standardizedFileURL
        self.operations = operations
        self.mode = mode
        self.constraint = constraint
        self.options = options
    }
}

public struct StandardDeleteResource: Sendable, Codable, Hashable {
    public var target: URL
    public var policy: StandardDeletePolicy

    public init(
        target: URL,
        policy: StandardDeletePolicy = .existing
    ) {
        self.target = target.standardizedFileURL
        self.policy = policy
    }
}
