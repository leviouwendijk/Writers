import Foundation
import TestFlows
import Writers

extension WritersFlowSuite {
    static var standardMutationAutomaticRollbackFlow: TestFlow {
        TestFlow(
            "standard-mutation-automatic-rollback",
            tags: [
                "mutation",
                "rollback",
                "automatic",
                "pass",
                "multi-file",
            ]
        ) {
            Step("rollback_applied restores previous state across multi-file pass") {
                let workspace = try TestWorkspace(
                    "standard-mutation-automatic-rollback-multifile"
                )
                defer {
                    workspace.remove()
                }

                let edited = workspace.file(
                    "edited.txt"
                )
                let created = workspace.file(
                    "created.txt"
                )
                let stale = workspace.file(
                    "stale.txt"
                )

                try automaticRollbackWrite(
                    "one\ntwo\n",
                    to: edited
                )
                try automaticRollbackWrite(
                    "alpha\n",
                    to: stale
                )

                let plan = try StandardWriter(
                    edited
                ).mutations.plan([
                    .editText(
                        at: edited,
                        operations: [
                            .replaceLineGuarded(
                                2,
                                expected: "two",
                                with: "TWO"
                            ),
                        ]
                    ),
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

                try automaticRollbackWrite(
                    "changed\n",
                    to: stale
                )

                let result = StandardWriter(
                    edited
                ).mutations.apply(
                    plan,
                    options: .init(
                        failure: .rollback_applied
                    )
                )

                try Expect.equal(
                    result.status,
                    .rolled_back,
                    "result.status"
                )
                try Expect.notNil(
                    result.failed,
                    "result.failed"
                )
                try Expect.equal(
                    result.records.count,
                    2,
                    "result.forward-records.count"
                )
                try Expect.equal(
                    result.applied.count,
                    2,
                    "result.applied.count"
                )

                let automaticRollback = try Expect.notNil(
                    result.automaticRollback,
                    "result.automaticRollback"
                )

                try Expect.equal(
                    automaticRollback.status,
                    .applied,
                    "automaticRollback.status"
                )
                try Expect.equal(
                    automaticRollback.records.count,
                    2,
                    "automaticRollback.records.count"
                )

                try Expect.equal(
                    try automaticRollbackRead(
                        edited
                    ),
                    "one\ntwo\n",
                    "edited.restored"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: created.path
                    ),
                    "created.deleted"
                )
                try Expect.equal(
                    try automaticRollbackRead(
                        stale
                    ),
                    "changed\n",
                    "stale.preserved"
                )

                try Expect.equal(
                    automaticRollback.records[0].target.standardizedFileURL.path,
                    created.standardizedFileURL.path,
                    "rollback.first-target"
                )
                try Expect.equal(
                    automaticRollback.records[1].target.standardizedFileURL.path,
                    edited.standardizedFileURL.path,
                    "rollback.second-target"
                )
            }

            Step("stop policy leaves already applied entries in place") {
                let workspace = try TestWorkspace(
                    "standard-mutation-stop-leaves-partial"
                )
                defer {
                    workspace.remove()
                }

                let edited = workspace.file(
                    "edited.txt"
                )
                let created = workspace.file(
                    "created.txt"
                )
                let stale = workspace.file(
                    "stale.txt"
                )

                try automaticRollbackWrite(
                    "one\ntwo\n",
                    to: edited
                )
                try automaticRollbackWrite(
                    "alpha\n",
                    to: stale
                )

                let plan = try StandardWriter(
                    edited
                ).mutations.plan([
                    .editText(
                        at: edited,
                        operations: [
                            .replaceLineGuarded(
                                2,
                                expected: "two",
                                with: "TWO"
                            ),
                        ]
                    ),
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

                try automaticRollbackWrite(
                    "changed\n",
                    to: stale
                )

                let result = StandardWriter(
                    edited
                ).mutations.apply(
                    plan,
                    options: .init(
                        failure: .stop
                    )
                )

                try Expect.equal(
                    result.status,
                    .partial,
                    "result.status"
                )
                try Expect.notNil(
                    result.failed,
                    "result.failed"
                )
                try Expect.isNil(
                    result.automaticRollback,
                    "result.automaticRollback"
                )
                try Expect.equal(
                    result.records.count,
                    2,
                    "result.records.count"
                )

                try Expect.equal(
                    try automaticRollbackRead(
                        edited
                    ),
                    "one\nTWO\n",
                    "edited.left-applied"
                )
                try Expect.equal(
                    try automaticRollbackRead(
                        created
                    ),
                    "created\n",
                    "created.left-applied"
                )
                try Expect.equal(
                    try automaticRollbackRead(
                        stale
                    ),
                    "changed\n",
                    "stale.preserved"
                )
            }
        }
    }
}

private func automaticRollbackWrite(
    _ content: String,
    to url: URL
) throws {
    try content.write(
        to: url,
        atomically: true,
        encoding: .utf8
    )
}

private func automaticRollbackRead(
    _ url: URL
) throws -> String {
    try String(
        contentsOf: url,
        encoding: .utf8
    )
}
