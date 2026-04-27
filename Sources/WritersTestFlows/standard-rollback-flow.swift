import Foundation
import TestFlows
import Writers

extension WritersFlowSuite {
    static var standardRollbackFlow: TestFlow {
        TestFlow(
            "standard-rollback",
            tags: [
                "mutation",
                "rollback",
                "pass",
            ]
        ) {
            Step("rollback create deletes created file") {
                let workspace = try TestWorkspace(
                    "standard-rollback-create"
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
                    "create.rollback"
                )

                let rollbackResult = StandardWriter(
                    target
                ).rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "create.rollback.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: target.path
                    ),
                    "create.rollback.file-missing"
                )
                try Expect.equal(
                    rollbackResult.records.count,
                    1,
                    "create.rollback.records.count"
                )
                try Expect.equal(
                    rollbackResult.records[0].operationKind,
                    .rollback,
                    "create.rollback.record.operation"
                )
                try Expect.equal(
                    rollbackResult.records[0].surfacedResourceChangeKind,
                    .deletion,
                    "create.rollback.record.resource"
                )
                try Expect.equal(
                    rollbackResult.records[0].surfacedDeltaKind,
                    .deletion,
                    "create.rollback.record.delta"
                )
            }

            Step("rollback edit restores previous text") {
                let workspace = try TestWorkspace(
                    "standard-rollback-edit"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "edited.txt"
                )

                try rollbackWriteLines(
                    [
                        "one",
                        "two",
                    ],
                    to: target
                )

                let plan = try StandardWriter(
                    target
                ).mutations.plan(
                    .editText(
                        at: target,
                        operations: [
                            .replaceLineGuarded(
                                2,
                                expected: "two",
                                with: "TWO"
                            ),
                        ]
                    )
                )
                let result = StandardWriter(
                    target
                ).mutations.apply(
                    plan
                )

                try Expect.equal(
                    try rollbackRead(
                        target
                    ),
                    "one\nTWO",
                    "edit.after-apply"
                )

                let rollback = try Expect.notNil(
                    result.rollback,
                    "edit.rollback"
                )
                let rollbackResult = StandardWriter(
                    target
                ).rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "edit.rollback.status"
                )
                try Expect.equal(
                    try rollbackRead(
                        target
                    ),
                    "one\ntwo",
                    "edit.after-rollback"
                )
                try Expect.equal(
                    rollbackResult.records[0].surfacedResourceChangeKind,
                    .update,
                    "edit.rollback.record.resource"
                )
            }

            Step("rollback delete recreates file") {
                let workspace = try TestWorkspace(
                    "standard-rollback-delete"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "deleted.txt"
                )

                try rollbackWriteLines(
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

                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: target.path
                    ),
                    "delete.after-apply"
                )

                let rollback = try Expect.notNil(
                    result.rollback,
                    "delete.rollback"
                )
                let rollbackResult = StandardWriter(
                    target
                ).rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "delete.rollback.status"
                )
                try Expect.equal(
                    try rollbackRead(
                        target
                    ),
                    "alpha\nbeta",
                    "delete.after-rollback"
                )
                try Expect.equal(
                    rollbackResult.records[0].surfacedResourceChangeKind,
                    .creation,
                    "delete.rollback.record.resource"
                )
            }

            Step("rollback pass runs in reverse action order") {
                let workspace = try TestWorkspace(
                    "standard-rollback-reverse-order"
                )
                defer {
                    workspace.remove()
                }

                let created = workspace.file(
                    "created.txt"
                )
                let deleted = workspace.file(
                    "deleted.txt"
                )

                try rollbackWriteLines(
                    [
                        "keep",
                    ],
                    to: deleted
                )

                let plan = try StandardWriter(
                    created
                ).mutations.plan([
                    .createText(
                        at: created,
                        content: "created\n"
                    ),
                    .delete(
                        at: deleted
                    ),
                ])
                let result = StandardWriter(
                    created
                ).mutations.apply(
                    plan
                )
                let rollback = try Expect.notNil(
                    result.rollback,
                    "reverse.rollback"
                )
                let rollbackResult = StandardWriter(
                    created
                ).rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "reverse.rollback.status"
                )
                try Expect.equal(
                    rollbackResult.records.count,
                    2,
                    "reverse.rollback.records.count"
                )
                try Expect.equal(
                    rollbackResult.records[0].target.standardizedFileURL.path,
                    deleted.standardizedFileURL.path,
                    "reverse.rollback.first-target"
                )
                try Expect.equal(
                    rollbackResult.records[1].target.standardizedFileURL.path,
                    created.standardizedFileURL.path,
                    "reverse.rollback.second-target"
                )
                try Expect.equal(
                    try rollbackRead(
                        deleted
                    ),
                    "keep",
                    "reverse.deleted-restored"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: created.path
                    ),
                    "reverse.created-deleted"
                )
            }

            Step("rollback blocks on drift") {
                let workspace = try TestWorkspace(
                    "standard-rollback-drift"
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
                    "drift.rollback"
                )

                try "tampered\n".write(
                    to: target,
                    atomically: true,
                    encoding: .utf8
                )

                let rollbackResult = StandardWriter(
                    target
                ).rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .failed,
                    "drift.rollback.status"
                )
                try Expect.notNil(
                    rollbackResult.failed,
                    "drift.rollback.failed"
                )
                try Expect.equal(
                    rollbackResult.records.count,
                    0,
                    "drift.rollback.records.count"
                )
                try Expect.equal(
                    try rollbackRead(
                        target
                    ),
                    "tampered\n",
                    "drift.rollback.content-preserved"
                )
            }

            Step("rollback_applied rolls back applied entries after mutation failure") {
                let workspace = try TestWorkspace(
                    "standard-rollback-automatic"
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

                try rollbackWriteLines(
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

                try rollbackWriteLines(
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
                    "automatic.status"
                )
                try Expect.notNil(
                    result.failed,
                    "automatic.failed"
                )
                try Expect.notNil(
                    result.automaticRollback,
                    "automatic.rollback"
                )
                try Expect.equal(
                    result.automaticRollback?.status,
                    .applied,
                    "automatic.rollback.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: created.path
                    ),
                    "automatic.created-rolled-back"
                )
                try Expect.equal(
                    try rollbackRead(
                        stale
                    ),
                    "changed",
                    "automatic.stale-preserved"
                )
            }
        }
    }
}

private func rollbackWriteLines(
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

private func rollbackRead(
    _ url: URL
) throws -> String {
    try String(
        contentsOf: url,
        encoding: .utf8
    )
}
