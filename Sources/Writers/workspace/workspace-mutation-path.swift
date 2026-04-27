import Path

public enum WorkspaceMutationPath: Sendable {
    case raw(String)
    case standard(StandardPath)
    case scoped(ScopedPath)

    public func authorize(
        in workspace: WorkspaceWriter,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        type: PathSegmentType? = .file
    ) throws -> AuthorizedPath {
        switch self {
        case .raw(let rawPath):
            return try workspace.authorize(
                rawPath,
                rootIdentifier: rootIdentifier,
                type: type
            )

        case .standard(let path):
            return try workspace.authorize(
                path,
                rootIdentifier: rootIdentifier,
                type: type
            )

        case .scoped(let path):
            return try workspace.authorize(
                path,
                rootIdentifier: rootIdentifier,
                type: type
            )
        }
    }
}
