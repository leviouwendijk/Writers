import Foundation
import TestFlows
import Writers

extension WritersFlowSuite {
    static var standardMutationFlow: TestFlow {
        TestFlow(
            "standard-mutation",
            tags: [
                "mutation",
                "pass",
                "resource-state",
                "planning",
                "apply",
                "drift",
            ]
        ) {
            Step("resource state distinguishes missing from empty text") {
                let workspace = try TestWorkspace(
                    "standard-mutation-resource-state"
                )
                defer {
                    workspace.remove()
                }

                let missing = workspace.file(
                    "missing.txt"
                )
                let empty = workspace.file(
                    "empty.txt"
                )

                try "".write(
                    to: empty,
                    atomically: true,
                    encoding: .utf8
                )

                let missingState = try StandardResourceState.read(
                    at: missing
                )
                let emptyState = try StandardResourceState.read(
                    at: empty
                )

                try Expect.false(
                    missingState.exists,
                    "missing.exists"
                )
                try Expect.true(
                    emptyState.exists,
                    "empty.exists"
                )

                guard case .missing = missingState else {
                    throw TestFlowAssertionFailure(
                        label: "missing.kind",
                        message: "expected missing resource state",
                        actual: String(
                            describing: missingState
                        ),
                        expected: "missing"
                    )
                }

                guard case .text(let text) = emptyState else {
                    throw TestFlowAssertionFailure(
                        label: "empty.kind",
                        message: "expected text resource state",
                        actual: String(
                            describing: emptyState
                        ),
                        expected: "text"
                    )
                }

                try Expect.equal(
                    text.content,
                    "",
                    "empty.content"
                )
                try Expect.equal(
                    text.bytes,
                    0,
                    "empty.bytes"
                )
                try Expect.equal(
                    text.lines,
                    0,
                    "empty.lines"
                )
            }

            Step("resource state detects binary data") {
                let workspace = try TestWorkspace(
                    "standard-mutation-resource-binary"
                )
                defer {
                    workspace.remove()
                }

                let binary = workspace.file(
                    "binary.bin"
                )

                try Data(
                    [
                        0xFF,
                        0x00,
                        0x01,
                    ]
                ).write(
                    to: binary,
                    options: .atomic
                )

                let state = try StandardResourceState.read(
                    at: binary
                )

                guard case .data(let data) = state else {
                    throw TestFlowAssertionFailure(
                        label: "binary.kind",
                        message: "expected data resource state",
                        actual: String(
                            describing: state
                        ),
                        expected: "data"
                    )
                }

                try Expect.equal(
                    data.bytes,
                    3,
                    "binary.bytes"
                )
            }

            Step("planning create has no side effects") {
                let workspace = try TestWorkspace(
                    "standard-mutation-plan-create"
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
                        content: "alpha\n"
                    )
                )

                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: target.path
                    ),
                    "plan.no-side-effect"
                )
                try Expect.equal(
                    plan.entries.count,
                    1,
                    "plan.entries.count"
                )
                try Expect.equal(
                    plan.report.entryCount,
                    1,
                    "plan.report.entryCount"
                )
                try Expect.equal(
                    plan.report.creates,
                    1,
                    "plan.report.creates"
                )
                try Expect.equal(
                    plan.report.updates,
                    0,
                    "plan.report.updates"
                )
                try Expect.equal(
                    plan.report.deletes,
                    0,
                    "plan.report.deletes"
                )
                try Expect.equal(
                    plan.entries[0].resource,
                    .creation,
                    "planned.resource"
                )
                try Expect.equal(
                    plan.entries[0].delta,
                    .addition,
                    "planned.delta"
                )

                guard case .missing = plan.entries[0].before else {
                    throw TestFlowAssertionFailure(
                        label: "planned.before",
                        message: "expected missing before-state",
                        actual: String(
                            describing: plan.entries[0].before
                        ),
                        expected: "missing"
                    )
                }

                guard case .text(let after) = plan.entries[0].after else {
                    throw TestFlowAssertionFailure(
                        label: "planned.after",
                        message: "expected text after-state",
                        actual: String(
                            describing: plan.entries[0].after
                        ),
                        expected: "text"
                    )
                }

                try Expect.equal(
                    after.content,
                    "alpha\n",
                    "planned.after.content"
                )

                guard case .delete_created_file = plan.entries[0].rollback else {
                    throw TestFlowAssertionFailure(
                        label: "planned.rollback",
                        message: "expected delete-created-file rollback action",
                        actual: String(
                            describing: plan.entries[0].rollback
                        ),
                        expected: "delete_created_file"
                    )
                }
            }

            Step("planning rejects duplicate targets") {
                let workspace = try TestWorkspace(
                    "standard-mutation-duplicate-target"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "same.txt"
                )

                try Expect.throwsError(
                    "duplicate-target"
                ) {
                    _ = try StandardWriter(
                        target
                    ).mutations.plan([
                        .createText(
                            at: target,
                            content: "alpha\n"
                        ),
                        .replaceText(
                            at: target,
                            content: "bravo\n",
                            policy: .upsert
                        ),
                    ])
                }
            }

            Step("planning enforces create and replace policies") {
                let workspace = try TestWorkspace(
                    "standard-mutation-policies"
                )
                defer {
                    workspace.remove()
                }

                let existing = workspace.file(
                    "existing.txt"
                )
                let missing = workspace.file(
                    "missing.txt"
                )

                try writeLines(
                    [
                        "alpha",
                    ],
                    to: existing
                )

                try Expect.throwsError(
                    "create-existing-rejected"
                ) {
                    _ = try StandardWriter(
                        existing
                    ).mutations.plan(
                        .createText(
                            at: existing,
                            content: "bravo\n",
                            policy: .missing
                        )
                    )
                }

                try Expect.throwsError(
                    "replace-missing-rejected"
                ) {
                    _ = try StandardWriter(
                        missing
                    ).mutations.plan(
                        .replaceText(
                            at: missing,
                            content: "bravo\n",
                            policy: .existing
                        )
                    )
                }

                _ = try StandardWriter(
                    missing
                ).mutations.plan(
                    .replaceText(
                        at: missing,
                        content: "bravo\n",
                        policy: .create
                    )
                )
            }

            Step("apply create and edit as one coherent pass") {
                let workspace = try TestWorkspace(
                    "standard-mutation-apply-create-edit"
                )
                defer {
                    workspace.remove()
                }

                let created = workspace.file(
                    "created.txt"
                )
                let edited = workspace.file(
                    "edited.txt"
                )

                try writeLines(
                    [
                        "one",
                        "two",
                    ],
                    to: edited
                )

                let plan = try StandardWriter(
                    created
                ).mutations.plan(
                    [
                        .createText(
                            at: created,
                            content: "alpha\n"
                        ),
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
                    ],
                    metadata: [
                        "reason": "test-pass",
                    ]
                )

                let result = StandardWriter(
                    created
                ).mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "result.status"
                )
                try Expect.isNil(
                    result.failed,
                    "result.failed"
                )
                try Expect.equal(
                    result.records.count,
                    2,
                    "result.records.count"
                )
                try Expect.equal(
                    result.applied.count,
                    2,
                    "result.applied.count"
                )
                try Expect.notNil(
                    result.rollback,
                    "result.rollback"
                )

                try Expect.equal(
                    try read(
                        created
                    ),
                    "alpha\n",
                    "created.content"
                )
                try Expect.equal(
                    try read(
                        edited
                    ),
                    "one\nTWO",
                    "edited.content"
                )

                try Expect.equal(
                    result.records[0].operationKind,
                    .create_text,
                    "record.0.operation"
                )
                try Expect.equal(
                    result.records[0].surfacedResourceChangeKind,
                    .creation,
                    "record.0.resource"
                )
                try Expect.equal(
                    result.records[0].surfacedDeltaKind,
                    .addition,
                    "record.0.delta"
                )
                try Expect.equal(
                    result.records[0].metadata[
                        WriteMutationMetadataKey.pass_count
                    ],
                    "2",
                    "record.0.pass_count"
                )
                try Expect.equal(
                    result.records[0].metadata[
                        "reason"
                    ],
                    "test-pass",
                    "record.0.metadata.reason"
                )

                try Expect.equal(
                    result.records[1].operationKind,
                    .edit_operations,
                    "record.1.operation"
                )
                try Expect.equal(
                    result.records[1].surfacedResourceChangeKind,
                    .update,
                    "record.1.resource"
                )
                try Expect.equal(
                    result.records[1].metadata[
                        WriteMutationMetadataKey.pass_index
                    ],
                    "2",
                    "record.1.pass_index"
                )
            }

            Step("apply delete records deletion") {
                let workspace = try TestWorkspace(
                    "standard-mutation-apply-delete"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "delete-me.txt"
                )

                try writeLines(
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

                try Expect.equal(
                    result.status,
                    .applied,
                    "delete.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: target.path
                    ),
                    "delete.file-exists"
                )
                try Expect.equal(
                    result.records.count,
                    1,
                    "delete.records.count"
                )
                try Expect.equal(
                    result.records[0].operationKind,
                    .delete_resource,
                    "delete.record.operation"
                )
                try Expect.equal(
                    result.records[0].surfacedResourceChangeKind,
                    .deletion,
                    "delete.record.resource"
                )
                try Expect.equal(
                    result.records[0].surfacedDeltaKind,
                    .deletion,
                    "delete.record.delta"
                )

                guard case .restore_text = plan.entries[0].rollback else {
                    throw TestFlowAssertionFailure(
                        label: "delete.rollback",
                        message: "expected restore-text rollback action",
                        actual: String(
                            describing: plan.entries[0].rollback
                        ),
                        expected: "restore_text"
                    )
                }
            }

            Step("apply stops on drift before later entries") {
                let workspace = try TestWorkspace(
                    "standard-mutation-drift"
                )
                defer {
                    workspace.remove()
                }

                let stale = workspace.file(
                    "stale.txt"
                )
                let later = workspace.file(
                    "later.txt"
                )

                try writeLines(
                    [
                        "alpha",
                    ],
                    to: stale
                )

                let plan = try StandardWriter(
                    stale
                ).mutations.plan([
                    .replaceText(
                        at: stale,
                        content: "bravo\n",
                        policy: .existing
                    ),
                    .createText(
                        at: later,
                        content: "later\n"
                    ),
                ])

                try writeLines(
                    [
                        "changed",
                    ],
                    to: stale
                )

                let result = StandardWriter(
                    stale
                ).mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .failed,
                    "drift.status"
                )
                try Expect.notNil(
                    result.failed,
                    "drift.failed"
                )
                try Expect.equal(
                    result.records.count,
                    0,
                    "drift.records.count"
                )
                try Expect.equal(
                    result.applied.count,
                    0,
                    "drift.applied.count"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: later.path
                    ),
                    "drift.later-not-created"
                )
                try Expect.equal(
                    try read(
                        stale
                    ),
                    "changed",
                    "drift.stale-content-preserved"
                )
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

private func read(
    _ url: URL
) throws -> String {
    try String(
        contentsOf: url,
        encoding: .utf8
    )
}
