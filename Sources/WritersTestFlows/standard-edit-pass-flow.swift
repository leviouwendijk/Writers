import Foundation
import TestFlows
import Writers

extension WritersFlowSuite {
    static var editPassFlow: TestFlow {
        TestFlow(
            "edit-pass",
            tags: [
                "edit",
                "pass",
                "multi-file",
                "rollback",
            ]
        ) {
            Step("plan and apply multi-file pass") {
                let workspace = try TestWorkspace(
                    "edit-pass-apply"
                )
                defer {
                    workspace.remove()
                }

                let first = workspace.file(
                    "first.txt"
                )
                let second = workspace.file(
                    "second.txt"
                )

                try writeLines(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: first
                )
                try writeLines(
                    [
                        "one",
                        "two",
                    ],
                    to: second
                )

                let editPass = StandardEditPass()
                let applyPlan = try editPass.prepare(
                    [
                        .init(
                            target: first,
                            plan: try StandardEditPlan(
                                operations: [
                                    .replaceLineGuarded(
                                        2,
                                        expected: "beta",
                                        with: "bravo"
                                    ),
                                ],
                                constraint: .bounded(
                                    scope: .lines([
                                        .init(
                                            uncheckedStart: 2,
                                            uncheckedEnd: 2
                                        ),
                                    ])
                                )
                            )
                        ),
                        .init(
                            target: second,
                            plan: try StandardEditPlan(
                                operations: [
                                    .insertLines(
                                        [
                                            "middle",
                                        ],
                                        atLine: 2
                                    ),
                                ],
                                constraint: .init(
                                    scope: .file,
                                    budget: .medium,
                                    operations: .all,
                                    guards: .none
                                )
                            )
                        ),
                    ],
                    options: .init(
                        write: .overwriteWithoutBackup
                    ),
                    metadata: [
                        "purpose": "test"
                    ]
                )

                try Expect.equal(
                    applyPlan.plan.fileCount,
                    2,
                    "apply.file-count"
                )

                try Expect.equal(
                    applyPlan.plan.operationCount,
                    2,
                    "apply.operation-count"
                )

                let result = try editPass.apply(
                    applyPlan
                )

                try Expect.equal(
                    result.records.count,
                    2,
                    "apply.records.count"
                )

                try Expect.equal(
                    result.passRecord.records.count,
                    2,
                    "apply.pass-record.records.count"
                )

                try Expect.equal(
                    result.passRecord.metadata[
                        "purpose"
                    ],
                    "test",
                    "apply.pass-record.metadata"
                )

                try Expect.equal(
                    try readText(
                        first
                    ),
                    [
                        "alpha",
                        "bravo",
                    ].joined(
                        separator: "\n"
                    ),
                    "apply.first.content"
                )

                try Expect.equal(
                    try readText(
                        second
                    ),
                    [
                        "one",
                        "middle",
                        "two",
                    ].joined(
                        separator: "\n"
                    ),
                    "apply.second.content"
                )

                try Expect.equal(
                    result.records[0].metadata[
                        WriteMutationMetadataKey.pass_id
                    ],
                    result.passRecord.id.uuidString.lowercased(),
                    "apply.record.pass-id"
                )
            }

            Step("reject pass apply when any target drifts") {
                let workspace = try TestWorkspace(
                    "edit-pass-apply-drift"
                )
                defer {
                    workspace.remove()
                }

                let first = workspace.file(
                    "first.txt"
                )
                let second = workspace.file(
                    "second.txt"
                )

                try writeLines(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: first
                )
                try writeLines(
                    [
                        "one",
                        "two",
                    ],
                    to: second
                )

                let editPass = StandardEditPass()
                let applyPlan = try editPass.prepare(
                    [
                        .init(
                            target: first,
                            plan: try StandardEditPlan(
                                operations: [
                                    .replaceLineGuarded(
                                        2,
                                        expected: "beta",
                                        with: "bravo"
                                    ),
                                ],
                                constraint: .bounded(
                                    scope: .lines([
                                        .init(
                                            uncheckedStart: 2,
                                            uncheckedEnd: 2
                                        ),
                                    ])
                                )
                            )
                        ),
                        .init(
                            target: second,
                            plan: try StandardEditPlan(
                                operations: [
                                    .replaceLineGuarded(
                                        2,
                                        expected: "two",
                                        with: "dos"
                                    ),
                                ],
                                constraint: .bounded(
                                    scope: .lines([
                                        .init(
                                            uncheckedStart: 2,
                                            uncheckedEnd: 2
                                        ),
                                    ])
                                )
                            )
                        ),
                    ],
                    options: .init(
                        write: .overwriteWithoutBackup
                    )
                )

                try writeLines(
                    [
                        "one",
                        "drifted",
                    ],
                    to: second
                )

                try Expect.throwsError(
                    "apply-drift.rejected"
                ) {
                    _ = try editPass.apply(
                        applyPlan
                    )
                }

                try Expect.equal(
                    try readText(
                        first
                    ),
                    [
                        "alpha",
                        "beta",
                    ].joined(
                        separator: "\n"
                    ),
                    "apply-drift.first.unchanged"
                )
            }

            Step("rollback pass restores all files") {
                let workspace = try TestWorkspace(
                    "edit-pass-rollback"
                )
                defer {
                    workspace.remove()
                }

                let first = workspace.file(
                    "first.txt"
                )
                let second = workspace.file(
                    "second.txt"
                )

                try writeLines(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: first
                )
                try writeLines(
                    [
                        "one",
                        "two",
                    ],
                    to: second
                )

                let editPass = StandardEditPass()
                let applyPlan = try editPass.prepare(
                    [
                        .init(
                            target: first,
                            plan: try StandardEditPlan(
                                operations: [
                                    .replaceLineGuarded(
                                        2,
                                        expected: "beta",
                                        with: "bravo"
                                    ),
                                ],
                                constraint: .bounded(
                                    scope: .lines([
                                        .init(
                                            uncheckedStart: 2,
                                            uncheckedEnd: 2
                                        ),
                                    ])
                                )
                            )
                        ),
                        .init(
                            target: second,
                            plan: try StandardEditPlan(
                                operations: [
                                    .insertLines(
                                        [
                                            "middle",
                                        ],
                                        atLine: 2
                                    ),
                                ],
                                constraint: .init(
                                    scope: .file,
                                    budget: .medium,
                                    operations: .all,
                                    guards: .none
                                )
                            )
                        ),
                    ],
                    options: .init(
                        write: .overwriteWithoutBackup
                    )
                )

                let applied = try editPass.apply(
                    applyPlan
                )
                let rollbackPlan = try editPass.rollbackPlan(
                    applied.passRecord,
                    options: .overwriteWithoutBackup
                )

                let rollback = try editPass.applyRollback(
                    rollbackPlan
                )

                try Expect.equal(
                    rollback.results.count,
                    2,
                    "rollback.results.count"
                )

                try Expect.equal(
                    rollback.passRecord.records.count,
                    2,
                    "rollback.pass-record.records.count"
                )

                try Expect.equal(
                    rollback.passRecord.metadata[
                        WriteMutationMetadataKey.rollback_of_pass
                    ],
                    applied.passRecord.id.uuidString.lowercased(),
                    "rollback.pass-record.rollback-of-pass"
                )

                try Expect.equal(
                    try readText(
                        first
                    ),
                    [
                        "alpha",
                        "beta",
                    ].joined(
                        separator: "\n"
                    ),
                    "rollback.first.content"
                )

                try Expect.equal(
                    try readText(
                        second
                    ),
                    [
                        "one",
                        "two",
                    ].joined(
                        separator: "\n"
                    ),
                    "rollback.second.content"
                )
            }

            Step("reject pass rollback when any target drifts") {
                let workspace = try TestWorkspace(
                    "edit-pass-rollback-drift"
                )
                defer {
                    workspace.remove()
                }

                let first = workspace.file(
                    "first.txt"
                )
                let second = workspace.file(
                    "second.txt"
                )

                try writeLines(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: first
                )
                try writeLines(
                    [
                        "one",
                        "two",
                    ],
                    to: second
                )

                let editPass = StandardEditPass()
                let applyPlan = try editPass.prepare(
                    [
                        .init(
                            target: first,
                            plan: try StandardEditPlan(
                                operations: [
                                    .replaceLineGuarded(
                                        2,
                                        expected: "beta",
                                        with: "bravo"
                                    ),
                                ],
                                constraint: .bounded(
                                    scope: .lines([
                                        .init(
                                            uncheckedStart: 2,
                                            uncheckedEnd: 2
                                        ),
                                    ])
                                )
                            )
                        ),
                        .init(
                            target: second,
                            plan: try StandardEditPlan(
                                operations: [
                                    .replaceLineGuarded(
                                        2,
                                        expected: "two",
                                        with: "dos"
                                    ),
                                ],
                                constraint: .bounded(
                                    scope: .lines([
                                        .init(
                                            uncheckedStart: 2,
                                            uncheckedEnd: 2
                                        ),
                                    ])
                                )
                            )
                        ),
                    ],
                    options: .init(
                        write: .overwriteWithoutBackup
                    )
                )

                let applied = try editPass.apply(
                    applyPlan
                )

                try writeLines(
                    [
                        "one",
                        "manual change",
                    ],
                    to: second
                )

                try Expect.throwsError(
                    "rollback-drift.rejected"
                ) {
                    _ = try editPass.rollbackPlan(
                        applied.passRecord,
                        options: .overwriteWithoutBackup
                    )
                }

                try Expect.equal(
                    try readText(
                        first
                    ),
                    [
                        "alpha",
                        "bravo",
                    ].joined(
                        separator: "\n"
                    ),
                    "rollback-drift.first.unchanged"
                )
            }

            Step("reject duplicate targets") {
                let workspace = try TestWorkspace(
                    "edit-pass-duplicate-target"
                )
                defer {
                    workspace.remove()
                }

                let file = workspace.file(
                    "sample.txt"
                )

                try writeLines(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: file
                )

                let plan = try StandardEditPlan(
                    operations: [
                        .replaceLineGuarded(
                            2,
                            expected: "beta",
                            with: "bravo"
                        ),
                    ],
                    constraint: .bounded(
                        scope: .lines([
                            .init(
                                uncheckedStart: 2,
                                uncheckedEnd: 2
                            ),
                        ])
                    )
                )

                try Expect.throwsError(
                    "duplicate-target.rejected"
                ) {
                    _ = try StandardEditPass().prepare(
                        [
                            .init(
                                target: file,
                                plan: plan
                            ),
                            .init(
                                target: file,
                                plan: plan
                            ),
                        ],
                        options: .init(
                            write: .overwriteWithoutBackup
                        )
                    )
                }
            }
        }
    }
}

private func writeLines(
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

private func readText(
    _ url: URL
) throws -> String {
    try String(
        contentsOf: url,
        encoding: .utf8
    )
}
