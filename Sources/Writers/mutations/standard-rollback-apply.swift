import Difference
import Foundation

public struct StandardMutationRollbackApplyOptions: Sendable {
    public var options: SafeWriteOptions

    public init(
        options: SafeWriteOptions = .overwriteWithoutBackup
    ) {
        self.options = options
    }
}

public enum StandardMutationRollbackStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case applied
    case partial
    case failed
}

public struct StandardMutationRollbackFailure: Sendable {
    public let actionIndex: Int
    public let target: URL?
    public let message: String

    public init(
        actionIndex: Int,
        target: URL?,
        message: String
    ) {
        self.actionIndex = actionIndex
        self.target = target?.standardizedFileURL
        self.message = message
    }
}

public struct StandardMutationRollbackResult: Sendable {
    public let id: UUID
    public let plan: StandardMutationRollbackPlan
    public let status: StandardMutationRollbackStatus
    public let records: [WriteMutationRecord]
    public let applied: [Int]
    public let failed: StandardMutationRollbackFailure?

    public init(
        id: UUID = .init(),
        plan: StandardMutationRollbackPlan,
        status: StandardMutationRollbackStatus,
        records: [WriteMutationRecord],
        applied: [Int],
        failed: StandardMutationRollbackFailure?
    ) {
        self.id = id
        self.plan = plan
        self.status = status
        self.records = records
        self.applied = applied
        self.failed = failed
    }
}

public struct StandardMutationRollbackApplier: Sendable {
    public init() {}

    public func apply(
        _ plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions = .init()
    ) -> StandardMutationRollbackResult {
        var records: [WriteMutationRecord] = []
        var applied: [Int] = []
        var failed: StandardMutationRollbackFailure?

        for pair in plan.actions.enumerated() {
            let index = pair.offset + 1
            let action = pair.element

            do {
                if let record = try apply(
                    action,
                    index: index,
                    plan: plan,
                    options: options
                ) {
                    records.append(
                        record
                    )
                }

                applied.append(
                    index
                )
            } catch {
                failed = .init(
                    actionIndex: index,
                    target: action.target,
                    message: String(
                        describing: error
                    )
                )

                break
            }
        }

        let status: StandardMutationRollbackStatus
        if failed == nil {
            status = .applied
        } else if applied.isEmpty {
            status = .failed
        } else {
            status = .partial
        }

        return .init(
            plan: plan,
            status: status,
            records: records,
            applied: applied,
            failed: failed
        )
    }

    private func apply(
        _ action: StandardMutationRollbackAction,
        index: Int,
        plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions
    ) throws -> WriteMutationRecord? {
        switch action {
        case .none:
            return nil

        case .delete_created_file(let action):
            return try deleteCreatedFile(
                action,
                index: index,
                plan: plan
            )

        case .restore_text(let action):
            return try restoreText(
                action,
                index: index,
                plan: plan,
                options: options
            )

        case .restore_data(let action):
            return try restoreData(
                action,
                index: index,
                plan: plan,
                options: options
            )
        }
    }

    private func deleteCreatedFile(
        _ action: StandardMutationDeleteCreatedFile,
        index: Int,
        plan: StandardMutationRollbackPlan
    ) throws -> WriteMutationRecord {
        let currentData = try IntegratedReader.data(
            at: action.target,
            missingFileReturnsEmpty: false
        )
        let actual = StandardContentFingerprint.fingerprint(
            for: currentData
        )

        guard actual == action.requiredCurrentFingerprint else {
            throw StandardMutationError.drift_detected(
                target: action.target,
                expected: action.requiredCurrentFingerprint,
                actual: actual
            )
        }

        try FileManager.default.removeItem(
            at: action.target
        )

        return .init(
            target: action.target,
            operationKind: .rollback,
            before: .init(
                data: currentData,
                storeContent: true
            ),
            after: nil,
            difference: nil,
            metadata: metadata(
                plan: plan,
                index: index,
                action: .delete_created_file,
                resource: .deletion,
                delta: .deletion
            )
        )
    }

    private func restoreText(
        _ action: StandardMutationRestoreText,
        index: Int,
        plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions
    ) throws -> WriteMutationRecord {
        let before = try StandardResourceState.read(
            at: action.target,
            encoding: action.encoding
        )

        try requireExpectedCurrent(
            before,
            target: action.target,
            expected: action.requiredCurrentFingerprint
        )

        let writeResult = try StandardWriter(
            action.target
        ).write(
            action.content,
            encoding: action.encoding,
            options: options.options
        )

        return writeResult.mutationRecord(
            operationKind: .rollback,
            difference: textDifference(
                before: before,
                after: action.content,
                target: action.target
            ),
            metadata: metadata(
                plan: plan,
                index: index,
                action: .restore_text,
                resource: before.exists ? .update : .creation,
                delta: before.exists ? .replacement : .addition
            )
        )
    }

    private func restoreData(
        _ action: StandardMutationRestoreData,
        index: Int,
        plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions
    ) throws -> WriteMutationRecord {
        let before = try StandardResourceState.read(
            at: action.target
        )

        try requireExpectedCurrent(
            before,
            target: action.target,
            expected: action.requiredCurrentFingerprint
        )

        let writeResult = try StandardWriter(
            action.target
        ).write(
            action.content,
            options: options.options
        )

        return writeResult.mutationRecord(
            operationKind: .rollback,
            difference: nil,
            metadata: metadata(
                plan: plan,
                index: index,
                action: .restore_data,
                resource: before.exists ? .update : .creation,
                delta: before.exists ? .replacement : .addition
            )
        )
    }

    private func requireExpectedCurrent(
        _ current: StandardResourceState,
        target: URL,
        expected: StandardContentFingerprint?
    ) throws {
        guard let expected else {
            guard !current.exists else {
                throw StandardMutationError.drift_detected(
                    target: target,
                    expected: nil,
                    actual: current.fingerprint
                )
            }

            return
        }

        guard current.fingerprint == expected else {
            throw StandardMutationError.drift_detected(
                target: target,
                expected: expected,
                actual: current.fingerprint
            )
        }
    }

    private func textDifference(
        before: StandardResourceState,
        after: String,
        target: URL
    ) -> WriteMutationDifferenceSummary? {
        let beforeText: String

        switch before {
        case .missing:
            beforeText = ""

        case .text(let state):
            beforeText = state.content

        case .data:
            return nil
        }

        return .init(
            WriteDifference.lines(
                old: beforeText,
                new: after,
                oldName: "\(target.lastPathComponent) (before rollback)",
                newName: "\(target.lastPathComponent) (after rollback)"
            )
        )
    }

    private func metadata(
        plan: StandardMutationRollbackPlan,
        index: Int,
        action: StandardMutationRollbackActionKind,
        resource: WriteResourceChangeKind,
        delta: WriteDeltaKind
    ) -> [String: String] {
        [
            WriteMutationMetadataKey.rollback_of: plan.source.uuidString.lowercased(),
            WriteMutationMetadataKey.rollback_strategy: WriteMutationRollbackStrategy.rollback_operations.rawValue,
            WriteMutationMetadataKey.resource_change: resource.rawValue,
            WriteMutationMetadataKey.delta_kind: delta.rawValue,
            WriteMutationMetadataKey.rollback_of_pass: plan.source.uuidString.lowercased(),
            WriteMutationMetadataKey.rollback_pass_id: plan.id.uuidString.lowercased(),
            WriteMutationMetadataKey.rollback_index: String(index),
            WriteMutationMetadataKey.rollback_count: String(plan.actions.count),
            WriteMutationMetadataKey.rollback_action: action.rawValue,
        ]
    }
}

public typealias StandardRollbackApplyOptions = StandardMutationRollbackApplyOptions
public typealias StandardRollbackStatus = StandardMutationRollbackStatus
public typealias StandardRollbackFailure = StandardMutationRollbackFailure
public typealias StandardRollbackResult = StandardMutationRollbackResult
public typealias StandardRollbackApplier = StandardMutationRollbackApplier

public extension WriteRollbackAPI {
    @discardableResult
    func apply(
        _ plan: StandardMutationRollbackPlan,
        options: StandardMutationRollbackApplyOptions = .init()
    ) -> StandardMutationRollbackResult {
        StandardMutationRollbackApplier().apply(
            plan,
            options: options
        )
    }
}
