import Foundation

public struct WriteResultBackupAPI: Sendable {
    public let result: WriteResult

    public init(
        result: WriteResult
    ) {
        self.result = result
    }

    public var record: WriteBackupRecord? {
        result.backupRecord
    }

    public var localURL: URL? {
        result.backupRecord?.storage?.localURL ?? result.backupURL
    }

    public var policy: WriteBackupPolicy? {
        result.backupRecord?.policy
    }
}

public struct WriteResultSnapshotsAPI: Sendable {
    public let result: WriteResult

    public init(
        result: WriteResult
    ) {
        self.result = result
    }

    public var before: WriteMutationSnapshot? {
        result.beforeSnapshot
    }

    public var after: WriteMutationSnapshot? {
        result.afterSnapshot
    }
}

public struct WriteResultSummaryAPI: Sendable {
    public let result: WriteResult

    public init(
        result: WriteResult
    ) {
        self.result = result
    }

    public var resource: WriteResourceChangeKind {
        switch (
            result.beforeSnapshot == nil,
            result.afterSnapshot == nil
        ) {
        case (true, false):
            return .creation

        case (false, false):
            return .update

        case (false, true):
            return .deletion

        case (true, true):
            return .unknown
        }
    }

    public var delta: WriteDeltaKind {
        guard let before = result.beforeSnapshot else {
            return result.afterSnapshot == nil ? .unknown : .addition
        }

        guard let after = result.afterSnapshot else {
            return .deletion
        }

        return before.fingerprint == after.fingerprint ? .unchanged : .replacement
    }
}

public extension WriteResult {
    var backup: WriteResultBackupAPI {
        .init(
            result: self
        )
    }

    var snapshots: WriteResultSnapshotsAPI {
        .init(
            result: self
        )
    }

    var summary: WriteResultSummaryAPI {
        .init(
            result: self
        )
    }
}
