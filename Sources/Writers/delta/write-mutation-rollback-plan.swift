import Foundation
import Readers

public struct WriteMutationRollbackPlan: Sendable, Codable, Hashable {
    public let record: WriteMutationRecord
    public let preview: WriteMutationRollbackPreview
    public let options: SafeWriteOptions
    public let encoding: TextEncoding
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
        self.encoding = TextEncoding(encoding)
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
        checkTarget: Bool = true,
        context: WriteExecutionContext = .init()
    ) throws -> WriteMutationRollbackPlan {
        .init(
            record: record,
            preview: try previewRollback(
                record,
                encoding: encoding,
                checkTarget: checkTarget,
                context: context
            ),
            options: options,
            encoding: encoding,
            checkTarget: checkTarget
        )
    }

    @discardableResult
    func applyRollback(
        _ plan: WriteMutationRollbackPlan,
        context: WriteExecutionContext = .init()
    ) throws -> WriteMutationRollbackResult {
        if plan.checkTarget,
           plan.record.target.standardizedFileURL != url.standardizedFileURL {
            throw WriteMutationRollbackError.target_mismatch(
                recordTarget: plan.record.target,
                writerTarget: url
            )
        }

        let current = try IntegratedReader.text(
            at: url,
            encoding: plan.encoding.foundation,
            missingFileReturnsEmpty: false,
            normalizeNewlines: false
        )

        if let expected = plan.record.rollbackGuard?.requiredCurrentFingerprint {
            let actual = StandardContentFingerprint.fingerprint(
                for: current
            )

            guard actual == expected else {
                throw WriteMutationRollbackError.guard_failed(
                    target: url,
                    expected: expected,
                    actual: actual
                )
            }
        }

        let writeResult = try write(
            plan.preview.rollbackContent,
            encoding: plan.encoding.foundation,
            options: plan.options,
            context: context
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
        _ plan: WriteMutationRollbackPlan,
        context: WriteExecutionContext = .init()
    ) throws -> WriteMutationRollbackResult {
        try writer.applyRollback(
            plan,
            context: context
        )
    }
}
