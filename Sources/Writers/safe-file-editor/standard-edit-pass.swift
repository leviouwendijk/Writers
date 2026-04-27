import Foundation

public enum StandardEditPassError: Error, Sendable, LocalizedError {
    case empty_pass
    case duplicate_target(URL)
    case drift_detected(
        target: URL,
        expected: StandardContentFingerprint,
        actual: StandardContentFingerprint
    )
    case missing_record_for_rollback_preview(UUID)

    public var errorDescription: String? {
        switch self {
        case .empty_pass:
            return "Edit pass cannot be empty."

        case .duplicate_target(let target):
            return "Edit pass contains duplicate target \(target.path). Merge same-file operations into one StandardEditBatchPlan first."

        case .drift_detected(let target, let expected, let actual):
            return "Edit pass drift detected for \(target.path). Expected base fingerprint \(expected), but found \(actual)."

        case .missing_record_for_rollback_preview(let id):
            return "Edit pass rollback preview has no matching mutation record for \(id.uuidString.lowercased())."
        }
    }
}

public struct StandardEditPassEdit: Sendable {
    public let target: URL
    public let plan: StandardEditPlan

    public init(
        target: URL,
        plan: StandardEditPlan
    ) {
        self.target = target.standardizedFileURL
        self.plan = plan
    }
}

public struct StandardEditPassEntry: Sendable {
    public let index: Int
    public let target: URL
    public let editPlan: StandardEditPlan
    public let batch: StandardEditBatchPlan

    public init(
        index: Int,
        target: URL,
        editPlan: StandardEditPlan,
        batch: StandardEditBatchPlan
    ) {
        self.index = index
        self.target = target.standardizedFileURL
        self.editPlan = editPlan
        self.batch = batch
    }

    public var operationCount: Int {
        editPlan.operations.count
    }

    public var result: StandardEditResult {
        batch.result
    }
}

public struct StandardEditPassPlan: Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let entries: [StandardEditPassEntry]
    public let metadata: [String: String]

    public init(
        id: UUID = .init(),
        createdAt: Date = .init(),
        entries: [StandardEditPassEntry],
        metadata: [String: String] = [:]
    ) throws {
        guard !entries.isEmpty else {
            throw StandardEditPassError.empty_pass
        }

        var seen = Set<String>()

        for entry in entries {
            let key = entry.target.standardizedFileURL.path

            guard !seen.contains(key) else {
                throw StandardEditPassError.duplicate_target(
                    entry.target
                )
            }

            seen.insert(
                key
            )
        }

        self.id = id
        self.createdAt = createdAt
        self.entries = entries
        self.metadata = metadata
    }

    public var operationCount: Int {
        entries.reduce(0) { partial, entry in
            partial + entry.operationCount
        }
    }

    public var fileCount: Int {
        entries.count
    }

    public var report: StandardEditPassReport {
        .init(
            self
        )
    }
}

public struct StandardEditPassEntryReport: Sendable, Codable, Hashable {
    public let index: Int
    public let target: URL
    public let operationCount: Int
    public let batch: StandardEditBatchReport

    public init(
        _ entry: StandardEditPassEntry
    ) {
        self.index = entry.index
        self.target = entry.target
        self.operationCount = entry.operationCount
        self.batch = entry.batch.report
    }
}

public struct StandardEditPassReport: Sendable, Codable, Hashable {
    public let id: UUID
    public let fileCount: Int
    public let operationCount: Int
    public let changedLineCount: Int
    public let insertedLineCount: Int
    public let deletedLineCount: Int
    public let entries: [StandardEditPassEntryReport]

    public init(
        _ plan: StandardEditPassPlan
    ) {
        self.id = plan.id
        self.fileCount = plan.fileCount
        self.operationCount = plan.operationCount
        self.changedLineCount = plan.entries.reduce(0) { partial, entry in
            partial + entry.result.changeCount
        }
        self.insertedLineCount = plan.entries.reduce(0) { partial, entry in
            partial + entry.result.insertions
        }
        self.deletedLineCount = plan.entries.reduce(0) { partial, entry in
            partial + entry.result.deletions
        }
        self.entries = plan.entries.map(
            StandardEditPassEntryReport.init
        )
    }
}

public struct StandardEditPassApplyPlan: Sendable {
    public let plan: StandardEditPassPlan
    public let options: StandardEditApplyOptions

    public init(
        plan: StandardEditPassPlan,
        options: StandardEditApplyOptions = .init()
    ) {
        self.plan = plan
        self.options = options
    }
}

public struct StandardEditPassApplyResult: Sendable {
    public let plan: StandardEditPassPlan
    public let results: [StandardEditResult]
    public let records: [WriteMutationRecord]
    public let passRecord: WriteMutationPassRecord

    public init(
        plan: StandardEditPassPlan,
        results: [StandardEditResult],
        records: [WriteMutationRecord],
        passRecord: WriteMutationPassRecord
    ) {
        self.plan = plan
        self.results = results
        self.records = records
        self.passRecord = passRecord
    }
}

public struct WriteMutationPassGuardEntry: Sendable, Codable, Hashable {
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

public struct WriteMutationPassRollbackGuard: Sendable, Codable, Hashable {
    public let entries: [WriteMutationPassGuardEntry]
    public let reason: String

    public init(
        entries: [WriteMutationPassGuardEntry],
        reason: String = "Every current file must still match its post-pass snapshot before automatic pass rollback."
    ) {
        self.entries = entries
        self.reason = reason
    }
}

public struct WriteMutationPassRecord: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let records: [WriteMutationRecord]
    public let rollbackGuard: WriteMutationPassRollbackGuard
    public let metadata: [String: String]

    public init(
        id: UUID = .init(),
        createdAt: Date = .init(),
        records: [WriteMutationRecord],
        rollbackGuard: WriteMutationPassRollbackGuard? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.records = records
        self.rollbackGuard = rollbackGuard ?? .init(
            entries: records.compactMap { record in
                guard let fingerprint = record.after?.fingerprint else {
                    return nil
                }

                return .init(
                    target: record.target,
                    requiredCurrentFingerprint: fingerprint
                )
            }
        )
        self.metadata = metadata
    }

    public var rollbackable: Bool {
        records.allSatisfy(\.hasRollbackPayload)
    }
}

public struct WriteMutationPassRollbackPreview: Sendable, Codable, Hashable {
    public let passID: UUID
    public let previews: [WriteMutationRollbackPreview]

    public init(
        passID: UUID,
        previews: [WriteMutationRollbackPreview]
    ) {
        self.passID = passID
        self.previews = previews
    }

    public var hasChanges: Bool {
        previews.contains(
            where: \.hasChanges
        )
    }
}

public struct StandardEditPassRollbackPlan: Sendable {
    public let record: WriteMutationPassRecord
    public let preview: WriteMutationPassRollbackPreview
    public let options: SafeWriteOptions
    public let encoding: String.Encoding

    public init(
        record: WriteMutationPassRecord,
        preview: WriteMutationPassRollbackPreview,
        options: SafeWriteOptions = .overwrite,
        encoding: String.Encoding = .utf8
    ) {
        self.record = record
        self.preview = preview
        self.options = options
        self.encoding = encoding
    }
}

public struct StandardEditPassRollbackResult: Sendable {
    public let plan: StandardEditPassRollbackPlan
    public let results: [WriteMutationRollbackResult]
    public let passRecord: WriteMutationPassRecord

    public init(
        plan: StandardEditPassRollbackPlan,
        results: [WriteMutationRollbackResult],
        passRecord: WriteMutationPassRecord
    ) {
        self.plan = plan
        self.results = results
        self.passRecord = passRecord
    }
}

public struct StandardEditPass: Sendable {
    public init() {}

    public func plan(
        _ edits: [StandardEditPassEdit],
        encoding: String.Encoding = .utf8,
        metadata: [String: String] = [:]
    ) throws -> StandardEditPassPlan {
        guard !edits.isEmpty else {
            throw StandardEditPassError.empty_pass
        }

        var entries: [StandardEditPassEntry] = []

        for pair in edits.enumerated() {
            let edit = pair.element
            let batch = try StandardEditor(
                edit.target
            ).batch(
                edit.plan,
                encoding: encoding
            )

            entries.append(
                .init(
                    index: pair.offset + 1,
                    target: edit.target,
                    editPlan: edit.plan,
                    batch: batch
                )
            )
        }

        return try .init(
            entries: entries,
            metadata: metadata
        )
    }

    public func prepare(
        _ edits: [StandardEditPassEdit],
        options: StandardEditApplyOptions = .init(),
        metadata: [String: String] = [:]
    ) throws -> StandardEditPassApplyPlan {
        try .init(
            plan: plan(
                edits,
                encoding: options.encoding,
                metadata: metadata
            ),
            options: options
        )
    }

    @discardableResult
    public func apply(
        _ applyPlan: StandardEditPassApplyPlan,
        storeContent: Bool = true
    ) throws -> StandardEditPassApplyResult {
        try requireCurrentBases(
            applyPlan
        )

        var results: [StandardEditResult] = []
        var records: [WriteMutationRecord] = []

        for entry in applyPlan.plan.entries {
            let result = try StandardEditor(
                entry.target
            ).apply(
                StandardEditBatchApplyPlan(
                    editPlan: entry.editPlan,
                    batch: entry.batch,
                    options: applyPlan.options
                )
            )
            let record = result.mutationRecord(
                operationKind: .edit_operations,
                storeContent: storeContent,
                metadata: passMetadata(
                    passID: applyPlan.plan.id,
                    entry: entry,
                    total: applyPlan.plan.entries.count,
                    base: applyPlan.plan.metadata
                )
            )

            results.append(
                result
            )
            records.append(
                record
            )
        }

        let passRecord = WriteMutationPassRecord(
            id: applyPlan.plan.id,
            createdAt: applyPlan.plan.createdAt,
            records: records,
            metadata: applyPlan.plan.metadata
        )

        return .init(
            plan: applyPlan.plan,
            results: results,
            records: records,
            passRecord: passRecord
        )
    }

    public func rollbackPlan(
        _ record: WriteMutationPassRecord,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditPassRollbackPlan {
        guard !record.records.isEmpty else {
            throw StandardEditPassError.empty_pass
        }

        let previews = try record.records.map { mutationRecord in
            try StandardWriter(
                mutationRecord.target
            ).previewRollback(
                mutationRecord,
                encoding: encoding
            )
        }

        return .init(
            record: record,
            preview: .init(
                passID: record.id,
                previews: previews
            ),
            options: options,
            encoding: encoding
        )
    }

    @discardableResult
    public func applyRollback(
        _ plan: StandardEditPassRollbackPlan
    ) throws -> StandardEditPassRollbackResult {
        let recordsByID = Dictionary(
            uniqueKeysWithValues: plan.record.records.map {
                (
                    $0.id,
                    $0
                )
            }
        )

        var results: [WriteMutationRollbackResult] = []

        for preview in plan.preview.previews.reversed() {
            guard let record = recordsByID[
                preview.recordID
            ] else {
                throw StandardEditPassError.missing_record_for_rollback_preview(
                    preview.recordID
                )
            }

            let rollbackPlan = try StandardWriter(
                preview.target
            ).rollbackPlan(
                record,
                encoding: plan.encoding,
                options: plan.options
            )
            let result = try StandardWriter(
                preview.target
            ).applyRollback(
                rollbackPlan
            )
            let recordWithPassMetadata = result.rollbackRecord.withMetadata(
                WriteMutationMetadata(
                    raw: result.rollbackRecord.metadata
                )
                .setting(
                    WriteMutationMetadataKey.pass_id,
                    to: plan.record.id.uuidString.lowercased()
                )
                .setting(
                    WriteMutationMetadataKey.rollback_of_pass,
                    to: plan.record.id.uuidString.lowercased()
                )
            )

            results.append(
                .init(
                    preview: result.preview,
                    writeResult: result.writeResult,
                    rollbackRecord: recordWithPassMetadata
                )
            )
        }

        let rollbackPassRecord = WriteMutationPassRecord(
            records: results.map(\.rollbackRecord),
            metadata: [
                WriteMutationMetadataKey.rollback_of_pass: plan.record.id.uuidString.lowercased(),
                WriteMutationMetadataKey.rollback_strategy: WriteMutationRollbackStrategy.before_snapshot.rawValue,
            ]
        )

        return .init(
            plan: plan,
            results: results,
            passRecord: rollbackPassRecord
        )
    }
}

private extension StandardEditPass {
    func requireCurrentBases(
        _ applyPlan: StandardEditPassApplyPlan
    ) throws {
        for entry in applyPlan.plan.entries {
            let current = try IntegratedReader.text(
                at: entry.target,
                encoding: applyPlan.options.encoding,
                missingFileReturnsEmpty: true,
                normalizeNewlines: false
            )
            let actual = StandardContentFingerprint.fingerprint(
                for: current
            )

            guard actual == entry.batch.base.fingerprint else {
                throw StandardEditPassError.drift_detected(
                    target: entry.target,
                    expected: entry.batch.base.fingerprint,
                    actual: actual
                )
            }
        }
    }

    func passMetadata(
        passID: UUID,
        entry: StandardEditPassEntry,
        total: Int,
        base: [String: String]
    ) -> [String: String] {
        base.merging(
            [
                WriteMutationMetadataKey.pass_id: passID.uuidString.lowercased(),
                WriteMutationMetadataKey.pass_index: String(entry.index),
                WriteMutationMetadataKey.pass_count: String(total),
            ]
        ) { _, new in
            new
        }
    }
}
