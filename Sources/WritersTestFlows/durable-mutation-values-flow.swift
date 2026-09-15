import Foundation
import TestFlows
import Writers

extension WritersFlowSuite {
    static var durableMutationValuesFlow: TestFlow {
        TestFlow(
            "durable-mutation-values",
            tags: [
                "mutation",
                "codable",
                "hashable",
                "backup",
            ]
        ) {
            Step("mutation-plan-codable-roundtrip") {
                let workspace = try TestWorkspace(
                    "mutation-plan-codable-roundtrip"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "created.txt"
                )
                let plan = try StandardMutationPlanner().plan(
                    [
                        .create_text(
                            .init(
                                target: target,
                                content: "created\n"
                            )
                        ),
                    ]
                )

                let decoded = try durableRoundTrip(
                    plan
                )

                try Expect.equal(
                    decoded,
                    plan,
                    "mutation.plan.roundtrip"
                )
            }

            Step("mutation-result-codable-roundtrip") {
                let workspace = try TestWorkspace(
                    "mutation-result-codable-roundtrip"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "created.txt"
                )
                let plan = try StandardMutationPlanner().plan(
                    [
                        .create_text(
                            .init(
                                target: target,
                                content: "created\n"
                            )
                        ),
                    ]
                )
                let result = StandardMutationApplier().apply(
                    plan
                )

                let decoded = try durableRoundTrip(
                    result
                )

                try Expect.equal(
                    decoded,
                    result,
                    "mutation.result.roundtrip"
                )
            }

            Step("mutation-rollback-plan-codable-roundtrip") {
                let workspace = try TestWorkspace(
                    "mutation-rollback-plan-codable-roundtrip"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "created.txt"
                )
                let plan = try StandardMutationPlanner().plan(
                    [
                        .create_text(
                            .init(
                                target: target,
                                content: "created\n"
                            )
                        ),
                    ]
                )
                let result = StandardMutationApplier().apply(
                    plan
                )
                let rollback = try Expect.notNil(
                    result.rollback,
                    "mutation.rollback.plan"
                )

                let decoded = try durableRoundTrip(
                    rollback
                )

                try Expect.equal(
                    decoded,
                    rollback,
                    "mutation.rollback.plan.roundtrip"
                )
            }

            Step("mutation-rollback-result-codable-roundtrip") {
                let workspace = try TestWorkspace(
                    "mutation-rollback-result-codable-roundtrip"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "created.txt"
                )
                let plan = try StandardMutationPlanner().plan(
                    [
                        .create_text(
                            .init(
                                target: target,
                                content: "created\n"
                            )
                        ),
                    ]
                )
                let result = StandardMutationApplier().apply(
                    plan
                )
                let rollback = try Expect.notNil(
                    result.rollback,
                    "mutation.rollback.result.plan"
                )
                let rollbackResult = StandardMutationRollbackApplier().apply(
                    rollback
                )

                let decoded = try durableRoundTrip(
                    rollbackResult
                )

                try Expect.equal(
                    decoded,
                    rollbackResult,
                    "mutation.rollback.result.roundtrip"
                )
            }

            Step("write-rollback-plan-codable-roundtrip") {
                let workspace = try TestWorkspace(
                    "write-rollback-plan-codable-roundtrip"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    target
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )
                let edit = try writer.editor.edit(
                    .replaceEntireFile(
                        with: "after\n"
                    ),
                    options: .overwriteWithoutBackup
                )
                let record = edit.mutationRecord(
                    operationKind: .write_text,
                    storeContent: true
                )
                let plan = try writer.rollbackPlan(
                    record,
                    options: .overwriteWithoutBackup
                )

                let decoded = try durableRoundTrip(
                    plan
                )

                try Expect.equal(
                    decoded,
                    plan,
                    "write.rollback.plan.roundtrip"
                )
            }

            Step("write-rollback-result-codable-roundtrip") {
                let workspace = try TestWorkspace(
                    "write-rollback-result-codable-roundtrip"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    target
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )
                let edit = try writer.editor.edit(
                    .replaceEntireFile(
                        with: "after\n"
                    ),
                    options: .overwriteWithoutBackup
                )
                let record = edit.mutationRecord(
                    operationKind: .write_text,
                    storeContent: true
                )
                let plan = try writer.rollbackPlan(
                    record,
                    options: .overwriteWithoutBackup
                )
                let result = try writer.applyRollback(
                    plan
                )

                let decoded = try durableRoundTrip(
                    result
                )

                try Expect.equal(
                    decoded,
                    result,
                    "write.rollback.result.roundtrip"
                )
            }

            Step("external-backup-policy-roundtrip") {
                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .external_store,
                    maxBackupSets: nil
                )

                let decoded = try durableRoundTrip(
                    options
                )

                try Expect.equal(
                    decoded,
                    options,
                    "external.backup.policy.options.roundtrip"
                )
                try Expect.equal(
                    decoded.backupPolicy,
                    .external_store,
                    "external.backup.policy.roundtrip"
                )
            }

            Step("external-backup-store-remains-execution-resource") {
                let workspace = try TestWorkspace(
                    "external-backup-store-remains-execution-resource"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "sample.txt"
                )
                let store = DirectoryBackupStore(
                    root: try workspace.directory(
                        "external-backups"
                    )
                )
                let writer = StandardWriter(
                    target
                )
                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .external_store,
                    maxBackupSets: nil
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let plan = try StandardMutationPlanner().plan(
                    [
                        .replace_text(
                            .init(
                                target: target,
                                content: "after\n",
                                options: options
                            )
                        ),
                    ]
                )
                let result = StandardMutationApplier().apply(
                    plan,
                    context: .init(
                        backupStore: store
                    )
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "external.execution-context.status"
                )

                let record = try Expect.notNil(
                    result.records.first,
                    "external.execution-context.record"
                )
                let backup = try Expect.notNil(
                    record.backupRecord,
                    "external.execution-context.backup"
                )
                let data = try Expect.notNil(
                    try store.loadBackup(
                        backup
                    ),
                    "external.execution-context.data"
                )

                try Expect.equal(
                    String(
                        decoding: data,
                        as: UTF8.self
                    ),
                    "before\n",
                    "external.execution-context.content"
                )
                try Expect.equal(
                    try workspace.read(target),
                    "after\n",
                    "external.execution-context.target"
                )
            }
        }
    }
}

private func durableRoundTrip<Value: Codable & Hashable>(
    _ value: Value
) throws -> Value {
    let data = try JSONEncoder().encode(
        value
    )

    return try JSONDecoder().decode(
        Value.self,
        from: data
    )
}
