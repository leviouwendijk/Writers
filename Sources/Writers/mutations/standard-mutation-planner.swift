import Difference
import Foundation

public struct StandardMutationPlanner: Sendable {
    public init() {}

    public func plan(
        _ entries: [StandardMutationEntry],
        metadata: [String: String] = [:]
    ) throws -> StandardMutationPlan {
        guard !entries.isEmpty else {
            throw StandardMutationError.empty_entries
        }

        try requireUniqueTargets(
            entries
        )

        let planned = try entries.enumerated().map { pair in
            try plan(
                pair.element,
                index: pair.offset + 1
            )
        }

        return try .init(
            entries: planned,
            metadata: metadata
        )
    }

    private func plan(
        _ entry: StandardMutationEntry,
        index: Int
    ) throws -> StandardPlannedMutation {
        switch entry {
        case .create_text(let entry):
            return try planCreateText(
                entry,
                index: index
            )

        case .replace_text(let entry):
            return try planReplaceText(
                entry,
                index: index
            )

        case .edit_text(let entry):
            return try planEditText(
                entry,
                index: index
            )

        case .delete(let entry):
            return try planDelete(
                entry,
                index: index
            )
        }
    }

    private func planCreateText(
        _ entry: StandardCreateText,
        index: Int
    ) throws -> StandardPlannedMutation {
        let before = try StandardResourceState.read(
            at: entry.target,
            encoding: entry.encoding
        )

        if before.exists {
            throw StandardMutationError.target_exists(
                entry.target
            )
        }

        let after = StandardResourceState.text(
            entry.content,
            encoding: entry.encoding
        )
        let diff = textDiff(
            before: before,
            after: after,
            target: entry.target
        )
        let writePlan = try StandardWriter(
            entry.target
        ).preflight.string(
            entry.content,
            encoding: entry.encoding,
            options: entry.options
        )

        return .init(
            index: index,
            entry: .create_text(entry),
            target: entry.target,
            before: before,
            after: after,
            diff: diff,
            resource: before.exists ? .update : .creation,
            delta: diff?.deltaKind ?? .addition,
            writePlan: writePlan,
            rollback: rollbackAction(
                target: entry.target,
                before: before,
                after: after,
                encoding: entry.encoding
            ),
            warnings: warnings(
                diff: diff
            )
        )
    }

    private func planReplaceText(
        _ entry: StandardReplaceText,
        index: Int
    ) throws -> StandardPlannedMutation {
        let before = try StandardResourceState.read(
            at: entry.target,
            encoding: entry.encoding
        )

        switch (
            before.exists,
            entry.policy
        ) {
        case (false, .existing):
            throw StandardMutationError.target_missing(
                entry.target
            )

        case (true, .create):
            throw StandardMutationError.target_exists(
                entry.target
            )

        case (true, .existing),
             (true, .upsert),
             (false, .create),
             (false, .upsert):
            break
        }

        let after = StandardResourceState.text(
            entry.content,
            encoding: entry.encoding
        )
        let diff = textDiff(
            before: before,
            after: after,
            target: entry.target
        )
        let writePlan = try StandardWriter(
            entry.target
        ).preflight.string(
            entry.content,
            encoding: entry.encoding,
            options: entry.options
        )

        return .init(
            index: index,
            entry: .replace_text(entry),
            target: entry.target,
            before: before,
            after: after,
            diff: diff,
            resource: before.exists ? .update : .creation,
            delta: diff?.deltaKind ?? .replacement,
            writePlan: writePlan,
            rollback: rollbackAction(
                target: entry.target,
                before: before,
                after: after,
                encoding: entry.encoding
            ),
            warnings: warnings(
                diff: diff
            )
        )
    }

    private func planEditText(
        _ entry: StandardEditText,
        index: Int
    ) throws -> StandardPlannedMutation {
        let before = try StandardResourceState.read(
            at: entry.target,
            encoding: entry.options.encoding
        )

        _ = try before.requireText(
            target: entry.target
        )

        let editPlan = try StandardEditPlan(
            operations: entry.operations,
            mode: entry.mode,
            constraint: entry.constraint
        )
        let editBatch = try StandardEditor(
            entry.target
        ).batch(
            editPlan,
            encoding: entry.options.encoding
        )
        let after = StandardResourceState.text(
            editBatch.result.editedContent,
            encoding: entry.options.encoding
        )
        let diff = WriteMutationDifferenceSummary(
            editBatch.result.difference
        )

        return .init(
            index: index,
            entry: .edit_text(entry),
            target: entry.target,
            before: before,
            after: after,
            diff: diff,
            resource: .update,
            delta: diff.deltaKind,
            editPlan: editPlan,
            editBatch: editBatch,
            rollback: rollbackAction(
                target: entry.target,
                before: before,
                after: after,
                encoding: entry.options.encoding
            ),
            warnings: warnings(
                diff: diff
            )
        )
    }

    private func planDelete(
        _ entry: StandardDeleteResource,
        index: Int
    ) throws -> StandardPlannedMutation {
        let before = try StandardResourceState.read(
            at: entry.target
        )

        if !before.exists,
           entry.policy == .existing {
            throw StandardMutationError.target_missing(
                entry.target
            )
        }

        let after = StandardResourceState.missing
        let diff = textDiff(
            before: before,
            after: after,
            target: entry.target
        )
        let warningCodes: [StandardMutationWarning] = before.exists
            ? []
            : [
                .delete_missing_ok,
            ]

        return .init(
            index: index,
            entry: .delete(entry),
            target: entry.target,
            before: before,
            after: after,
            diff: diff,
            resource: before.exists ? .deletion : .unknown,
            delta: before.exists ? .deletion : .unchanged,
            rollback: rollbackAction(
                target: entry.target,
                before: before,
                after: after,
                encoding: .utf8
            ),
            warnings: warningCodes
        )
    }

    private func requireUniqueTargets(
        _ entries: [StandardMutationEntry]
    ) throws {
        var seen = Set<String>()

        for entry in entries {
            let target = entry.target.standardizedFileURL
            let key = target.path

            guard !seen.contains(key) else {
                throw StandardMutationError.duplicate_target(
                    target
                )
            }

            seen.insert(
                key
            )
        }
    }

    private func textDiff(
        before: StandardResourceState,
        after: StandardResourceState,
        target: URL
    ) -> WriteMutationDifferenceSummary? {
        guard let old = before.textContent ?? missingText(
            before
        ),
              let new = after.textContent ?? missingText(
                after
              )
        else {
            return nil
        }

        return .init(
            WriteDifference.lines(
                old: old,
                new: new,
                oldName: "\(target.lastPathComponent) (before)",
                newName: "\(target.lastPathComponent) (after)"
            )
        )
    }

    private func missingText(
        _ state: StandardResourceState
    ) -> String? {
        switch state {
        case .missing:
            return ""

        case .text(let value):
            return value.content

        case .data:
            return nil
        }
    }

    private func rollbackAction(
        target: URL,
        before: StandardResourceState,
        after: StandardResourceState,
        encoding: String.Encoding
    ) -> StandardMutationRollbackAction {
        switch (
            before,
            after
        ) {
        case (.missing, .text(let after)):
            return .delete_created_file(
                .init(
                    target: target,
                    requiredCurrentFingerprint: after.fingerprint
                )
            )

        case (.missing, .data(let after)):
            return .delete_created_file(
                .init(
                    target: target,
                    requiredCurrentFingerprint: after.fingerprint
                )
            )

        case (.text(let before), .text(let after)):
            return .restore_text(
                .init(
                    target: target,
                    content: before.content,
                    encoding: encoding,
                    requiredCurrentFingerprint: after.fingerprint
                )
            )

        case (.text(let before), .missing):
            return .restore_text(
                .init(
                    target: target,
                    content: before.content,
                    encoding: encoding,
                    requiredCurrentFingerprint: nil
                )
            )

        case (.data(let before), .data(let after)):
            return .restore_data(
                .init(
                    target: target,
                    content: before.content,
                    requiredCurrentFingerprint: after.fingerprint
                )
            )

        case (.data(let before), .missing):
            return .restore_data(
                .init(
                    target: target,
                    content: before.content,
                    requiredCurrentFingerprint: nil
                )
            )

        case (.missing, .missing):
            return .none

        case (.data(let before), .text(let after)):
            return .restore_data(
                .init(
                    target: target,
                    content: before.content,
                    requiredCurrentFingerprint: after.fingerprint
                )
            )

        case (.text(let before), .data(let after)):
            return .restore_text(
                .init(
                    target: target,
                    content: before.content,
                    encoding: encoding,
                    requiredCurrentFingerprint: after.fingerprint
                )
            )
        }
    }

    private func warnings(
        diff: WriteMutationDifferenceSummary?
    ) -> [StandardMutationWarning] {
        guard let diff else {
            return [
                .binary_resource,
            ]
        }

        guard diff.hasChanges else {
            return [
                .no_changes,
            ]
        }

        return []
    }
}
