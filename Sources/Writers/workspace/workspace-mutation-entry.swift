import Foundation
import Path

public enum WorkspaceMutationEntry: Sendable {
    case create_text(WorkspaceCreateText)
    case replace_text(WorkspaceReplaceText)
    case edit_text(WorkspaceEditText)
    case delete(WorkspaceDeleteResource)

    public func standardEntry(
        in workspace: WorkspaceWriter
    ) throws -> StandardMutationEntry {
        switch self {
        case .create_text(let entry):
            return try entry.standardEntry(
                in: workspace
            )

        case .replace_text(let entry):
            return try entry.standardEntry(
                in: workspace
            )

        case .edit_text(let entry):
            return try entry.standardEntry(
                in: workspace
            )

        case .delete(let entry):
            return try entry.standardEntry(
                in: workspace
            )
        }
    }
}

public struct WorkspaceCreateText: Sendable {
    public var target: WorkspaceMutationPath
    public var rootIdentifier: PathAccessRootIdentifier?
    public var content: String
    public var encoding: String.Encoding
    public var options: SafeWriteOptions

    public init(
        target: WorkspaceMutationPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        content: String,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) {
        self.target = target
        self.rootIdentifier = rootIdentifier
        self.content = content
        self.encoding = encoding
        self.options = options
    }

    public func standardEntry(
        in workspace: WorkspaceWriter
    ) throws -> StandardMutationEntry {
        let authorized = try target.authorize(
            in: workspace,
            rootIdentifier: rootIdentifier,
            type: .file
        )

        return .createText(
            at: authorized.absoluteURL,
            content: content,
            encoding: encoding,
            options: options
        )
    }
}

public struct WorkspaceReplaceText: Sendable {
    public var target: WorkspaceMutationPath
    public var rootIdentifier: PathAccessRootIdentifier?
    public var content: String
    public var policy: StandardReplacePolicy
    public var encoding: String.Encoding
    public var options: SafeWriteOptions

    public init(
        target: WorkspaceMutationPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        content: String,
        policy: StandardReplacePolicy = .existing,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) {
        self.target = target
        self.rootIdentifier = rootIdentifier
        self.content = content
        self.policy = policy
        self.encoding = encoding
        self.options = options
    }

    public func standardEntry(
        in workspace: WorkspaceWriter
    ) throws -> StandardMutationEntry {
        let authorized = try target.authorize(
            in: workspace,
            rootIdentifier: rootIdentifier,
            type: .file
        )

        return .replaceText(
            at: authorized.absoluteURL,
            content: content,
            policy: policy,
            encoding: encoding,
            options: options
        )
    }
}

public struct WorkspaceEditText: Sendable {
    public var target: WorkspaceMutationPath
    public var rootIdentifier: PathAccessRootIdentifier?
    public var operations: [StandardEditOperation]
    public var mode: StandardEditMode
    public var constraint: StandardEditConstraint
    public var options: StandardEditApplyOptions

    public init(
        target: WorkspaceMutationPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        constraint: StandardEditConstraint = .unrestricted,
        options: StandardEditApplyOptions = .init()
    ) {
        self.target = target
        self.rootIdentifier = rootIdentifier
        self.operations = operations
        self.mode = mode
        self.constraint = constraint
        self.options = options
    }

    public func standardEntry(
        in workspace: WorkspaceWriter
    ) throws -> StandardMutationEntry {
        let authorized = try target.authorize(
            in: workspace,
            rootIdentifier: rootIdentifier,
            type: .file
        )

        return .editText(
            at: authorized.absoluteURL,
            operations: operations,
            mode: mode,
            constraint: constraint,
            options: options
        )
    }
}

public struct WorkspaceDeleteResource: Sendable {
    public var target: WorkspaceMutationPath
    public var rootIdentifier: PathAccessRootIdentifier?
    public var policy: StandardDeletePolicy
    public var type: PathSegmentType?

    public init(
        target: WorkspaceMutationPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        policy: StandardDeletePolicy = .existing,
        type: PathSegmentType? = .file
    ) {
        self.target = target
        self.rootIdentifier = rootIdentifier
        self.policy = policy
        self.type = type
    }

    public func standardEntry(
        in workspace: WorkspaceWriter
    ) throws -> StandardMutationEntry {
        let authorized = try target.authorize(
            in: workspace,
            rootIdentifier: rootIdentifier,
            type: type
        )

        return .delete(
            at: authorized.absoluteURL,
            policy: policy
        )
    }
}
