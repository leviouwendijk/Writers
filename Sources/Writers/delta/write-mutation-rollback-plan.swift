import Foundation

public struct WriteMutationRollbackPlan: Sendable {
    public let record: WriteMutationRecord
    public let preview: WriteMutationRollbackPreview
    public let options: SafeWriteOptions
    public let encoding: String.Encoding
    public let checkTarget: Bool

    public init(
        record: WriteMutationRecord,
        preview: WriteMutationRollbackPreview,
        options: SafeWriteOptions = .overwrite,
        encoding: String.Encoding = .utf8,
        checkTarget: Bool = true
    ) {
        self.record = record
        self.preview = preview
        self.options = options
        self.encoding = encoding
        self.checkTarget = checkTarget
    }

    public var metadata: [String: String] {
        [
            WriteMutationMetadataKey.rollback_of: record.id.uuidString.lowercased(),
            WriteMutationMetadataKey.rollback_strategy: preview.strategy.rawValue,
            WriteMutationMetadataKey.resource_change: WriteResourceChangeKind.update.rawValue,
            WriteMutationMetadataKey.delta_kind: WriteDeltaKind.replacement.rawValue,
        ]
    }
}

public extension StandardWriter {
    func rollbackPlan(
        _ record: WriteMutationRecord,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite,
        checkTarget: Bool = true
    ) throws -> WriteMutationRollbackPlan {
        .init(
            record: record,
            preview: try previewRollback(
                record,
                encoding: encoding,
                checkTarget: checkTarget
            ),
            options: options,
            encoding: encoding,
            checkTarget: checkTarget
        )
    }

    @discardableResult
    func applyRollback(
        _ plan: WriteMutationRollbackPlan
    ) throws -> WriteMutationRollbackResult {
        let writeResult = try write(
            plan.preview.rollbackContent,
            encoding: plan.encoding,
            options: plan.options
        )

        let rollbackRecord = writeResult.mutationRecord(
            operationKind: .rollback,
            metadata: plan.metadata
        )

        return .init(
            preview: plan.preview,
            writeResult: writeResult,
            rollbackRecord: rollbackRecord
        )
    }
}

public extension WriteRollbackAPI {
    func plan(
        _ record: WriteMutationRecord,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite,
        checkTarget: Bool = true
    ) throws -> WriteMutationRollbackPlan {
        try writer.rollbackPlan(
            record,
            encoding: encoding,
            options: options,
            checkTarget: checkTarget
        )
    }

    @discardableResult
    func apply(
        _ plan: WriteMutationRollbackPlan
    ) throws -> WriteMutationRollbackResult {
        try writer.applyRollback(
            plan
        )
    }
}
