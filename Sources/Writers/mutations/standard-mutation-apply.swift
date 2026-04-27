import Foundation

public struct StandardMutationApplyOptions: Sendable, Codable, Hashable {
    public var failure: StandardMutationFailurePolicy

    public init(
        failure: StandardMutationFailurePolicy = .stop
    ) {
        self.failure = failure
    }
}

public enum StandardMutationStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case applied
    case partial
    case failed
    case rolled_back
}

public struct StandardMutationFailure: Sendable {
    public let entryID: UUID
    public let index: Int
    public let target: URL
    public let message: String

    public init(
        entryID: UUID,
        index: Int,
        target: URL,
        message: String
    ) {
        self.entryID = entryID
        self.index = index
        self.target = target.standardizedFileURL
        self.message = message
    }
}

public struct StandardMutationResult: Sendable {
    public let id: UUID
    public let plan: StandardMutationPlan
    public let status: StandardMutationStatus
    public let records: [WriteMutationRecord]
    public let applied: [UUID]
    public let failed: StandardMutationFailure?
    public let rollback: StandardMutationRollbackPlan?
    public let automaticRollback: StandardMutationRollbackResult?

    public init(
        id: UUID = .init(),
        plan: StandardMutationPlan,
        status: StandardMutationStatus,
        records: [WriteMutationRecord],
        applied: [UUID],
        failed: StandardMutationFailure?,
        rollback: StandardMutationRollbackPlan?,
        automaticRollback: StandardMutationRollbackResult? = nil
    ) {
        self.id = id
        self.plan = plan
        self.status = status
        self.records = records
        self.applied = applied
        self.failed = failed
        self.rollback = rollback
        self.automaticRollback = automaticRollback
    }
}

public struct StandardMutationApplier: Sendable {
    public init() {}

    public func apply(
        _ plan: StandardMutationPlan,
        options: StandardMutationApplyOptions = .init()
    ) -> StandardMutationResult {
        var records: [WriteMutationRecord] = []
        var applied: [UUID] = []
        var failed: StandardMutationFailure?

        for entry in plan.entries {
            do {
                try entry.before.requireCurrent(
                    at: entry.target,
                    encoding: entry.encoding
                )

                if let record = try apply(
                    entry,
                    passID: plan.id,
                    passCount: plan.entries.count,
                    metadata: plan.metadata
                ) {
                    records.append(
                        record
                    )
                }

                applied.append(
                    entry.id
                )
            } catch {
                failed = .init(
                    entryID: entry.id,
                    index: entry.index,
                    target: entry.target,
                    message: String(
                        describing: error
                    )
                )

                break
            }
        }

        let rollback = rollbackPlan(
            source: plan.id,
            entries: plan.entries,
            applied: Set(applied)
        )

        let automaticRollback: StandardMutationRollbackResult?
        if failed != nil,
           options.failure == .rollback_applied,
           let rollback {
            automaticRollback = StandardMutationRollbackApplier().apply(
                rollback
            )
        } else {
            automaticRollback = nil
        }

        let status: StandardMutationStatus
        if failed == nil {
            status = .applied
        } else if applied.isEmpty {
            status = .failed
        } else if automaticRollback?.status == .applied {
            status = .rolled_back
        } else {
            status = .partial
        }

        return .init(
            plan: plan,
            status: status,
            records: records,
            applied: applied,
            failed: failed,
            rollback: rollback,
            automaticRollback: automaticRollback
        )
    }

    private func apply(
        _ planned: StandardPlannedMutation,
        passID: UUID,
        passCount: Int,
        metadata: [String: String]
    ) throws -> WriteMutationRecord? {
        switch planned.entry {
        case .create_text(let entry):
            return try applyCreateText(
                entry,
                planned: planned,
                passID: passID,
                passCount: passCount,
                metadata: metadata
            )

        case .replace_text(let entry):
            return try applyReplaceText(
                entry,
                planned: planned,
                passID: passID,
                passCount: passCount,
                metadata: metadata
            )

        case .edit_text(let entry):
            return try applyEditText(
                entry,
                planned: planned,
                passID: passID,
                passCount: passCount,
                metadata: metadata
            )

        case .delete(let entry):
            return try applyDelete(
                entry,
                planned: planned,
                passID: passID,
                passCount: passCount,
                metadata: metadata
            )
        }
    }

    private func applyCreateText(
        _ entry: StandardCreateText,
        planned: StandardPlannedMutation,
        passID: UUID,
        passCount: Int,
        metadata: [String: String]
    ) throws -> WriteMutationRecord {
        let result = try StandardWriter(
            entry.target
        ).write(
            entry.content,
            encoding: entry.encoding,
            options: entry.options
        )

        return result.mutationRecord(
            operationKind: planned.before.exists ? .replace_text : .create_text,
            difference: planned.diff,
            metadata: passMetadata(
                planned: planned,
                passID: passID,
                passCount: passCount,
                base: metadata
            )
        )
    }

    private func applyReplaceText(
        _ entry: StandardReplaceText,
        planned: StandardPlannedMutation,
        passID: UUID,
        passCount: Int,
        metadata: [String: String]
    ) throws -> WriteMutationRecord {
        let result = try StandardWriter(
            entry.target
        ).write(
            entry.content,
            encoding: entry.encoding,
            options: entry.options
        )

        return result.mutationRecord(
            operationKind: planned.before.exists ? .replace_text : .create_text,
            difference: planned.diff,
            metadata: passMetadata(
                planned: planned,
                passID: passID,
                passCount: passCount,
                base: metadata
            )
        )
    }

    private func applyEditText(
        _ entry: StandardEditText,
        planned: StandardPlannedMutation,
        passID: UUID,
        passCount: Int,
        metadata: [String: String]
    ) throws -> WriteMutationRecord {
        guard let editPlan = planned.editPlan,
              let editBatch = planned.editBatch
        else {
            throw StandardMutationError.target_not_text(
                entry.target
            )
        }

        let applyPlan = try StandardEditBatchApplyPlan(
            editPlan: editPlan,
            batch: editBatch,
            options: entry.options
        )
        let result = try StandardEditor(
            entry.target
        ).apply(
            applyPlan
        )

        return result.mutationRecord(
            id: planned.id,
            operationKind: .edit_operations,
            metadata: passMetadata(
                planned: planned,
                passID: passID,
                passCount: passCount,
                base: metadata
            )
        )
    }

    private func applyDelete(
        _ entry: StandardDeleteResource,
        planned: StandardPlannedMutation,
        passID: UUID,
        passCount: Int,
        metadata: [String: String]
    ) throws -> WriteMutationRecord? {
        guard planned.before.exists else {
            return .init(
                id: planned.id,
                target: entry.target,
                operationKind: .delete_resource,
                before: nil,
                after: nil,
                difference: planned.diff,
                metadata: passMetadata(
                    planned: planned,
                    passID: passID,
                    passCount: passCount,
                    base: metadata
                )
            )
        }

        try FileManager.default.removeItem(
            at: entry.target
        )

        return .init(
            id: planned.id,
            target: entry.target,
            operationKind: .delete_resource,
            before: planned.before.snapshot,
            after: nil,
            difference: planned.diff,
            metadata: passMetadata(
                planned: planned,
                passID: passID,
                passCount: passCount,
                base: metadata
            )
        )
    }

    private func rollbackPlan(
        source: UUID,
        entries: [StandardPlannedMutation],
        applied: Set<UUID>
    ) -> StandardMutationRollbackPlan? {
        let actions = entries
            .filter {
                applied.contains(
                    $0.id
                )
            }
            .reversed()
            .map(\.rollback)

        guard !actions.isEmpty else {
            return nil
        }

        return .init(
            source: source,
            actions: Array(
                actions
            )
        )
    }

    private func passMetadata(
        planned: StandardPlannedMutation,
        passID: UUID,
        passCount: Int,
        base: [String: String]
    ) -> [String: String] {
        var out = base

        out[
            WriteMutationMetadataKey.pass_id
        ] = passID.uuidString.lowercased()
        out[
            WriteMutationMetadataKey.pass_index
        ] = String(
            planned.index
        )
        out[
            WriteMutationMetadataKey.pass_count
        ] = String(
            passCount
        )
        out[
            WriteMutationMetadataKey.resource_change
        ] = planned.resource.rawValue
        out[
            WriteMutationMetadataKey.delta_kind
        ] = planned.delta.rawValue

        return out
    }
}

private extension StandardPlannedMutation {
    var encoding: String.Encoding {
        switch entry {
        case .create_text(let entry):
            return entry.encoding

        case .replace_text(let entry):
            return entry.encoding

        case .edit_text(let entry):
            return entry.options.encoding

        case .delete:
            return .utf8
        }
    }
}
