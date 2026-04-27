import Foundation
import Path

public struct WorkspaceWriter: Sendable {
    public let access: PathAccessController
    public let writer: MutationWriter

    public init(
        access: PathAccessController,
        writer: MutationWriter = .init()
    ) {
        self.access = access
        self.writer = writer
    }

    public init(
        root: URL,
        policy: PathAccessPolicy = .defaults.workspace,
        rootIdentifier: PathAccessRootIdentifier = .project,
        label: String = "Project",
        details: String? = nil,
        writer: MutationWriter = .init()
    ) throws {
        try self.init(
            access: .project(
                scope: .init(
                    root: root,
                    policy: policy
                ),
                identifier: rootIdentifier,
                label: label,
                details: details
            ),
            writer: writer
        )
    }

    public var mutations: WorkspaceMutationAPI {
        .init(
            workspace: self
        )
    }

    public var rollbacks: MutationRollbackAPI {
        writer.rollbacks
    }

    public func authorize(
        _ rawPath: String,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        type: PathSegmentType? = .file
    ) throws -> AuthorizedPath {
        try access.authorize(
            rawPath,
            rootIdentifier: rootIdentifier,
            type: type
        )
    }

    public func authorize(
        _ path: StandardPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        type: PathSegmentType? = nil
    ) throws -> AuthorizedPath {
        try access.authorize(
            path,
            rootIdentifier: rootIdentifier,
            type: type
        )
    }

    public func authorize(
        _ path: ScopedPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        type: PathSegmentType? = nil
    ) throws -> AuthorizedPath {
        try access.authorize(
            path,
            rootIdentifier: rootIdentifier,
            type: type
        )
    }

    public func file(
        _ rawPath: String,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        type: PathSegmentType? = .file
    ) throws -> FileWriter {
        let authorized = try authorize(
            rawPath,
            rootIdentifier: rootIdentifier,
            type: type
        )

        return writer.file(
            authorized.absoluteURL
        )
    }

    public func file(
        _ path: StandardPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        type: PathSegmentType? = nil
    ) throws -> FileWriter {
        let authorized = try authorize(
            path,
            rootIdentifier: rootIdentifier,
            type: type
        )

        return writer.file(
            authorized.absoluteURL
        )
    }

    public func file(
        _ path: ScopedPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        type: PathSegmentType? = nil
    ) throws -> FileWriter {
        let authorized = try authorize(
            path,
            rootIdentifier: rootIdentifier,
            type: type
        )

        return writer.file(
            authorized.absoluteURL
        )
    }
}
