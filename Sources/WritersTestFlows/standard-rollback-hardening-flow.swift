import Foundation
import TestFlows
import Writers

extension WritersFlowSuite {
    static var standardRollbackHardeningFlow: TestFlow {
        TestFlow(
            "standard-rollback-hardening",
            tags: [
                "mutation",
                "rollback",
                "metadata",
                "binary",
                "drift",
            ]
        ) {
            Step("rollback metadata exposes typed pass fields") {
                let workspace = try TestWorkspace(
                    "standard-rollback-hardening-metadata"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "created.txt"
                )

                let plan = try StandardWriter(
                    target
                ).mutations.plan(
                    .createText(
                        at: target,
                        content: "created\n"
                    )
                )
                let result = StandardWriter(
                    target
                ).mutations.apply(
                    plan
                )
                let rollback = try Expect.notNil(
                    result.rollback,
                    "metadata.rollback"
                )
                let rollbackResult = StandardWriter(
                    target
                ).rollbacks.apply(
                    rollback
                )

                let record = try Expect.notNil(
                    rollbackResult.records.first,
                    "metadata.rollback-record"
                )

                try Expect.equal(
                    record.rollbackOfPassID,
                    plan.id,
                    "metadata.rollback-of-pass"
                )
                try Expect.equal(
                    record.rollbackPassID,
                    rollback.id,
                    "metadata.rollback-pass-id"
                )
                try Expect.equal(
                    record.rollbackIndex,
                    1,
                    "metadata.rollback-index"
                )
                try Expect.equal(
                    record.rollbackCount,
                    1,
                    "metadata.rollback-count"
                )
                try Expect.equal(
                    record.mutationRollbackAction,
                    .delete_created_file,
                    "metadata.rollback-action"
                )
            }

            Step("rollback delete blocks when deleted file was recreated") {
                let workspace = try TestWorkspace(
                    "standard-rollback-hardening-delete-drift"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "deleted.txt"
                )

                try hardeningWriteLines(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: target
                )

                let plan = try StandardWriter(
                    target
                ).mutations.plan(
                    .delete(
                        at: target
                    )
                )
                let result = StandardWriter(
                    target
                ).mutations.apply(
                    plan
                )
                let rollback = try Expect.notNil(
                    result.rollback,
                    "delete-drift.rollback"
                )

                try hardeningWriteLines(
                    [
                        "tampered",
                    ],
                    to: target
                )

                let rollbackResult = StandardWriter(
                    target
                ).rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .failed,
                    "delete-drift.status"
                )
                try Expect.notNil(
                    rollbackResult.failed,
                    "delete-drift.failed"
                )
                try Expect.equal(
                    rollbackResult.records.count,
                    0,
                    "delete-drift.records"
                )
                try Expect.equal(
                    try hardeningRead(
                        target
                    ),
                    "tampered",
                    "delete-drift.content-preserved"
                )
            }

            Step("rollback binary delete restores exact bytes") {
                let workspace = try TestWorkspace(
                    "standard-rollback-hardening-binary"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "payload.bin"
                )
                let bytes = Data(
                    [
                        0x00,
                        0xFF,
                        0x12,
                        0x34,
                        0x56,
                    ]
                )

                try bytes.write(
                    to: target,
                    options: .atomic
                )

                let plan = try StandardWriter(
                    target
                ).mutations.plan(
                    .delete(
                        at: target
                    )
                )
                let result = StandardWriter(
                    target
                ).mutations.apply(
                    plan
                )

                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: target.path
                    ),
                    "binary.deleted"
                )

                let rollback = try Expect.notNil(
                    result.rollback,
                    "binary.rollback"
                )
                let rollbackResult = StandardWriter(
                    target
                ).rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "binary.rollback.status"
                )
                try Expect.equal(
                    try Data(
                        contentsOf: target
                    ),
                    bytes,
                    "binary.restored-bytes"
                )
                try Expect.equal(
                    rollbackResult.records[0].mutationRollbackAction,
                    .restore_data,
                    "binary.rollback-action"
                )
            }

            Step("mutation result exposes forward and rollback records") {
                let workspace = try TestWorkspace(
                    "standard-rollback-hardening-result-accessors"
                )
                defer {
                    workspace.remove()
                }

                let created = workspace.file(
                    "created.txt"
                )
                let stale = workspace.file(
                    "stale.txt"
                )

                try hardeningWriteLines(
                    [
                        "alpha",
                    ],
                    to: stale
                )

                let plan = try StandardWriter(
                    created
                ).mutations.plan([
                    .createText(
                        at: created,
                        content: "created\n"
                    ),
                    .replaceText(
                        at: stale,
                        content: "bravo\n",
                        policy: .existing
                    ),
                ])

                try hardeningWriteLines(
                    [
                        "changed",
                    ],
                    to: stale
                )

                let result = StandardWriter(
                    created
                ).mutations.apply(
                    plan,
                    options: .init(
                        failure: .rollback_applied
                    )
                )

                try Expect.equal(
                    result.status,
                    .rolled_back,
                    "accessors.status"
                )
                try Expect.true(
                    result.rolledBack,
                    "accessors.rolled-back"
                )
                try Expect.equal(
                    result.forwardRecords.count,
                    1,
                    "accessors.forward-records"
                )
                try Expect.equal(
                    result.rollbackRecords.count,
                    1,
                    "accessors.rollback-records"
                )
                try Expect.equal(
                    result.allRecords.count,
                    2,
                    "accessors.all-records"
                )
            }
        }
    }
}

private func hardeningWriteLines(
    _ lines: [String],
    to url: URL
) throws {
    try lines.joined(
        separator: "\n"
    ).write(
        to: url,
        atomically: true,
        encoding: .utf8
    )
}

private func hardeningRead(
    _ url: URL
) throws -> String {
    try String(
        contentsOf: url,
        encoding: .utf8
    )
}
