import Foundation
import Position
import TestFlows
import Writers

extension WritersFlowSuite {
    static var editBatchFlow: TestFlow {
        TestFlow(
            "edit-batch",
            tags: [
                "edit",
                "batch",
                "staging",
                "provenance",
                "apply",
            ]
        ) {
            Step("plan stages operations sequentially") {
                let workspace = try TestWorkspace(
                    "edit-batch-sequential-plan"
                )
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )

                try write(
                    [
                        "alpha",
                        "beta",
                        "charlie",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
                )

                let batch = try editor.batch([
                    .insertLines(
                        [
                            "inserted",
                        ],
                        atLine: 2
                    ),
                    .replaceLineGuarded(
                        3,
                        expected: "beta",
                        with: "bravo"
                    ),
                ])

                try Expect.equal(
                    batch.steps.count,
                    2,
                    "sequential.steps.count"
                )

                try Expect.equal(
                    batch.result.editedContent,
                    [
                        "alpha",
                        "inserted",
                        "bravo",
                        "charlie",
                    ].joined(
                        separator: "\n"
                    ),
                    "sequential.final-content"
                )

                try Expect.equal(
                    batch.report.operationCount,
                    2,
                    "sequential.report.operation-count"
                )

                try Expect.equal(
                    batch.report.stepCount,
                    2,
                    "sequential.report.step-count"
                )

                try Expect.equal(
                    batch.steps[0].operationKind,
                    .insert_lines,
                    "sequential.step-1.kind"
                )

                try Expect.equal(
                    batch.steps[1].operationKind,
                    .replace_line_guarded,
                    "sequential.step-2.kind"
                )

                try Expect.isEmpty(
                    batch.steps[0].touch.originalRanges,
                    "sequential.step-1.original-ranges"
                )

                try Expect.equal(
                    renderedRanges(
                        batch.steps[1].touch.originalRanges
                    ),
                    [
                        "2...2",
                    ],
                    "sequential.step-2.original-ranges"
                )

                try Expect.false(
                    batch.steps[1].touch.overlapsPriorStep,
                    "sequential.step-2.overlaps-prior-step"
                )
            }

            Step("diagnose edits that touch prior insertion") {
                let workspace = try TestWorkspace(
                    "edit-batch-prior-insertion"
                )
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )

                try write(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
                )

                let batch = try editor.batch([
                    .insertLines(
                        [
                            "inserted",
                        ],
                        atLine: 2
                    ),
                    .replaceLineGuarded(
                        2,
                        expected: "inserted",
                        with: "changed"
                    ),
                ])

                let step = batch.steps[1]

                try Expect.true(
                    step.touch.overlapsPriorStep,
                    "prior-insertion.overlaps-prior-step"
                )

                try Expect.equal(
                    step.touch.priorStepIndexes,
                    [
                        1,
                    ],
                    "prior-insertion.prior-step-indexes"
                )

                try Expect.contains(
                    step.diagnostics.map(\.code),
                    .touches_prior_insertion,
                    "prior-insertion.diagnostic"
                )

                try Expect.equal(
                    batch.result.editedContent,
                    [
                        "alpha",
                        "changed",
                        "beta",
                    ].joined(
                        separator: "\n"
                    ),
                    "prior-insertion.final-content"
                )
            }

            Step("diagnose edits that rewrite same original range") {
                let workspace = try TestWorkspace(
                    "edit-batch-same-original-range"
                )
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )

                try write(
                    [
                        "alpha",
                        "beta",
                        "charlie",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
                )

                let batch = try editor.batch([
                    .replaceLineGuarded(
                        2,
                        expected: "beta",
                        with: "bravo"
                    ),
                    .replaceLineGuarded(
                        2,
                        expected: "bravo",
                        with: "bravo-final"
                    ),
                ])

                let step = batch.steps[1]
                let codes = step.diagnostics.map(\.code)

                try Expect.true(
                    step.touch.overlapsPriorStep,
                    "same-original.overlaps-prior-step"
                )

                try Expect.equal(
                    step.touch.priorStepIndexes,
                    [
                        1,
                    ],
                    "same-original.prior-step-indexes"
                )

                try Expect.equal(
                    renderedRanges(
                        step.touch.originalRanges
                    ),
                    [
                        "2...2",
                    ],
                    "same-original.original-ranges"
                )

                try Expect.contains(
                    codes,
                    .touches_prior_replacement,
                    "same-original.replacement-diagnostic"
                )

                try Expect.contains(
                    codes,
                    .touches_same_original_range,
                    "same-original.same-range-diagnostic"
                )

                try Expect.equal(
                    batch.result.editedContent,
                    [
                        "alpha",
                        "bravo-final",
                        "charlie",
                    ].joined(
                        separator: "\n"
                    ),
                    "same-original.final-content"
                )
            }

            Step("apply batch writes exact planned final content") {
                let workspace = try TestWorkspace(
                    "edit-batch-apply"
                )
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )

                try write(
                    [
                        "alpha",
                        "beta",
                        "charlie",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
                )

                let plan = try StandardEditPlan(
                    operations: [
                        .insertLines(
                            [
                                "inserted",
                            ],
                            atLine: 2
                        ),
                        .replaceLineGuarded(
                            3,
                            expected: "beta",
                            with: "bravo"
                        ),
                    ],
                    constraint: .init(
                        scope: .file,
                        budget: .medium,
                        operations: .all,
                        guards: .none
                    )
                )

                let applyPlan = try editor.prepareBatch(
                    plan,
                    options: .init(
                        write: .overwriteWithoutBackup
                    )
                )

                let result = try editor.apply(
                    applyPlan
                )

                try Expect.true(
                    result.performedWrite,
                    "apply.performed-write"
                )

                try Expect.equal(
                    try read(
                        url
                    ),
                    [
                        "alpha",
                        "inserted",
                        "bravo",
                        "charlie",
                    ].joined(
                        separator: "\n"
                    ),
                    "apply.file-content"
                )

                try Expect.equal(
                    result.editedFingerprint,
                    applyPlan.batch.final.fingerprint,
                    "apply.final-fingerprint"
                )
            }

            Step("reject stale batch apply") {
                let workspace = try TestWorkspace(
                    "edit-batch-stale-apply"
                )
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )

                try write(
                    [
                        "alpha",
                        "beta",
                        "charlie",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
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

                let applyPlan = try editor.prepareBatch(
                    plan,
                    options: .init(
                        write: .overwriteWithoutBackup
                    )
                )

                try write(
                    [
                        "alpha",
                        "drifted",
                        "charlie",
                    ],
                    to: url
                )

                try Expect.throwsError(
                    "stale-batch.apply"
                ) {
                    _ = try editor.apply(
                        applyPlan
                    )
                }
            }

            Step("plan snapshot mode against original line coordinates") {
                let workspace = try TestWorkspace(
                    "edit-batch-snapshot-mode"
                )
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )

                try write(
                    [
                        "alpha",
                        "beta",
                        "charlie",
                        "delta",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
                )

                let batch = try editor.batch(
                    [
                        .insertLines(
                            [
                                "inserted",
                            ],
                            atLine: 2
                        ),
                        .replaceLine(
                            3,
                            with: "changed-charlie"
                        ),
                    ],
                    mode: .snapshot
                )

                try Expect.equal(
                    batch.mode,
                    .snapshot,
                    "snapshot.mode"
                )

                try Expect.equal(
                    batch.steps.count,
                    2,
                    "snapshot.steps.count"
                )

                try Expect.equal(
                    batch.result.editedContent,
                    [
                        "alpha",
                        "inserted",
                        "beta",
                        "changed-charlie",
                        "delta",
                    ].joined(
                        separator: "\n"
                    ),
                    "snapshot.final-content"
                )

                try Expect.equal(
                    renderedRanges(
                        batch.steps[1].touch.originalRanges
                    ),
                    [
                        "3...3",
                    ],
                    "snapshot.step-2.original-ranges"
                )

                try Expect.false(
                    batch.steps[1].touch.overlapsPriorStep,
                    "snapshot.step-2.overlaps-prior-step"
                )
            }
        }
    }
}

private func write(
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

private func renderedRanges(
    _ ranges: [LineRange]
) -> [String] {
    ranges.map {
        "\($0.start)...\($0.end)"
    }
}
