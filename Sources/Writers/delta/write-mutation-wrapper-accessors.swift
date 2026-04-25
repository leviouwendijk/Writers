import Foundation

public struct WriteMutationSummaryAPI: Sendable {
    public let record: WriteMutationRecord

    public init(
        record: WriteMutationRecord
    ) {
        self.record = record
    }

    public var resource: WriteResourceChangeKind {
        record.surface.resource
    }

    public var delta: WriteDeltaKind {
        record.surface.delta
    }

    public var rollbackable: Bool {
        record.surface.rollback.available
    }
}

public struct WriteRollbackAPI: Sendable {
    public let writer: StandardWriter

    public init(
        writer: StandardWriter
    ) {
        self.writer = writer
    }

    public func preview(
        _ record: WriteMutationRecord,
        encoding: String.Encoding = .utf8,
        checkTarget: Bool = true
    ) throws -> WriteMutationRollbackPreview {
        try writer.previewRollback(
            record,
            encoding: encoding,
            checkTarget: checkTarget
        )
    }

    @discardableResult
    public func apply(
        _ record: WriteMutationRecord,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite,
        checkTarget: Bool = true
    ) throws -> WriteMutationRollbackResult {
        try writer.rollback(
            record,
            encoding: encoding,
            options: options,
            checkTarget: checkTarget
        )
    }
}

public extension WriteMutationRecord {
    var summary: WriteMutationSummaryAPI {
        .init(
            record: self
        )
    }
}

public extension StandardWriter {
    var rollbacks: WriteRollbackAPI {
        .init(
            writer: self
        )
    }
}
