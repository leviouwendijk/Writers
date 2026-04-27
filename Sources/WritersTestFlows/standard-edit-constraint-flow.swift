import Foundation
import Position
import TestFlows
import Writers

extension WritersFlowSuite {
    static var editConstraintFlow: TestFlow {
        TestFlow(
            "edit-constraints",
            tags: [
                "edit",
                "constraint",
                "guard",
                "budget",
                "scope",
                "apply",
            ]
        ) {
            Step("reject unguarded existing-line edits") {
                let constraint = StandardEditConstraint.presets.smallGuarded(
                    scope: .lines([
                        .init(
                            uncheckedStart: 2,
                            uncheckedEnd: 2
                        ),
                    ])
                )

                try expectViolation(
                    .operation_requires_guard,
                    "unguarded replaceLine is rejected"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLine(
                            2,
                            with: "bravo"
                        ),
                        constraint: constraint
                    )
                }
            }

            Step("accept guarded line replacement inside scope") {
                let workspace = try TestWorkspace(
                    "edit-constraints-guarded-line"
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

                let constraint = StandardEditConstraint.presets.smallGuarded(
                    scope: .lines([
                        .init(
                            uncheckedStart: 2,
                            uncheckedEnd: 2
                        ),
                    ])
                )

                let plan = try StandardEditPlan(
                    operation: .replaceLineGuarded(
                        2,
                        expected: "beta",
                        with: "bravo"
                    ),
                    constraint: constraint
                )

                let preview = try editor.preview(
                    plan
                )

                try Expect.equal(
                    preview.editedContent,
                    [
                        "alpha",
                        "bravo",
                        "charlie",
                    ].joined(
                        separator: "\n"
                    ),
                    "guarded-line.preview"
                )

                try Expect.equal(
                    preview.report.counts.operations,
                    1,
                    "guarded-line.operation-count"
                )

                try Expect.equal(
                    preview.report.operations,
                    [
                        .replace_line_guarded,
                    ],
                    "guarded-line.operation-kind"
                )
            }

            Step("reject unguarded insertions when insertion guards are required") {
                let constraint = StandardEditConstraint.presets.smallGuarded(
                    scope: .insertions([
                        2,
                    ])
                )

                try expectViolation(
                    .insertion_requires_guard,
                    "unguarded insertLines requires guarded insertion site"
                ) {
                    _ = try StandardEditPlan(
                        operation: .insertLines(
                            [
                                "inserted",
                            ],
                            atLine: 2
                        ),
                        constraint: constraint
                    )
                }
            }

            Step("reject operations outside explicit operation set") {
                let constraint = StandardEditConstraint(
                    scope: .file,
                    budget: .small,
                    operations: .guarded,
                    guards: .none
                )

                try expectViolation(
                    .operation_not_allowed,
                    "unguarded replaceLine is outside guarded-only operation set"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLine(
                            2,
                            with: "bravo"
                        ),
                        constraint: constraint
                    )
                }
            }

            Step("accept guarded insertion at allowed insertion site") {
                let workspace = try TestWorkspace(
                    "edit-constraints-guarded-insertion"
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
                        "charlie",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
                )

                let constraint = StandardEditConstraint.presets.smallGuarded(
                    scope: .insertions([
                        2,
                    ])
                )

                let plan = try StandardEditPlan(
                    operation: .insertLinesGuarded(
                        [
                            "beta",
                        ],
                        atLine: 2,
                        site: .init(
                            before: [
                                "alpha",
                            ],
                            after: [
                                "charlie",
                            ]
                        )
                    ),
                    constraint: constraint
                )

                let preview = try editor.preview(
                    plan
                )

                try Expect.equal(
                    preview.editedContent,
                    [
                        "alpha",
                        "beta",
                        "charlie",
                    ].joined(
                        separator: "\n"
                    ),
                    "guarded-insertion.preview"
                )

                try Expect.equal(
                    preview.report.operations,
                    [
                        .insert_lines_guarded,
                    ],
                    "guarded-insertion.operation-kind"
                )
            }

            Step("reject guarded insertion when site context does not match") {
                let workspace = try TestWorkspace(
                    "edit-constraints-insertion-site-mismatch"
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
                        "delta",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
                )

                let constraint = StandardEditConstraint.presets.smallGuarded(
                    scope: .insertions([
                        2,
                    ])
                )

                let plan = try StandardEditPlan(
                    operation: .insertLinesGuarded(
                        [
                            "beta",
                        ],
                        atLine: 2,
                        site: .init(
                            before: [
                                "alpha",
                            ],
                            after: [
                                "charlie",
                            ]
                        )
                    ),
                    constraint: constraint
                )

                try Expect.throwsError(
                    "guarded insertion site mismatch"
                ) {
                    _ = try editor.preview(
                        plan
                    )
                }
            }

            Step("reject wide replacement by budget after preview") {
                let workspace = try TestWorkspace(
                    "edit-constraints-budget"
                )
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )

                try write(
                    [
                        "line 1",
                        "line 2",
                        "line 3",
                        "line 4",
                        "line 5",
                        "line 6",
                        "line 7",
                        "line 8",
                        "line 9",
                        "line 10",
                        "line 11",
                        "line 12",
                    ],
                    to: url
                )

                let editor = StandardEditor(
                    url
                )

                let constraint = StandardEditConstraint(
                    scope: .file,
                    budget: .small,
                    operations: .precise,
                    guards: .none
                )

                try expectViolation(
                    .deleted_exceeded,
                    "wide replacement exceeds deleted-line budget"
                ) {
                    _ = try editor.preview(
                        .replaceLines(
                            .init(
                                uncheckedStart: 1,
                                uncheckedEnd: 12
                            ),
                            with: [
                                "replacement",
                            ]
                        ),
                        mode: .snapshot,
                        constraint: constraint
                    )
                }
            }

            Step("reject operation outside line scope before preview") {
                let constraint = StandardEditConstraint(
                    scope: .lines([
                        .init(
                            uncheckedStart: 4,
                            uncheckedEnd: 6
                        ),
                    ]),
                    budget: .small,
                    operations: .precise,
                    guards: .none
                )

                try expectViolation(
                    .operation_outside_scope,
                    "replaceLines outside line scope is rejected"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLines(
                            .init(
                                uncheckedStart: 1,
                                uncheckedEnd: 2
                            ),
                            with: [
                                "replacement",
                            ]
                        ),
                        constraint: constraint
                    )
                }
            }

            Step("reject unguardable operation under guarded policy") {
                let constraint = StandardEditConstraint(
                    scope: .file,
                    budget: .small,
                    operations: .all,
                    guards: .guarded
                )

                try expectViolation(
                    .unguardable_operation_denied,
                    "replaceUnique is denied by guarded policy"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceUnique(
                            of: "beta",
                            with: "bravo"
                        ),
                        constraint: constraint
                    )
                }
            }

            Step("apply approved preview writes exact edited content") {
                let workspace = try TestWorkspace(
                    "edit-constraints-apply-approved-preview"
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
                    operation: .replaceLineGuarded(
                        2,
                        expected: "beta",
                        with: "bravo"
                    ),
                    constraint: .bounded(
                        scope: .lines([
                            .init(
                                uncheckedStart: 2,
                                uncheckedEnd: 2
                            ),
                        ])
                    )
                )

                let preview = try editor.preview(
                    plan
                )

                let result = try editor.apply(
                    preview,
                    plan: plan,
                    options: .init(
                        write: .overwriteWithoutBackup
                    )
                )

                try Expect.equal(
                    result.performedWrite,
                    true,
                    "approved-preview.performed-write"
                )

                try Expect.equal(
                    try read(
                        url
                    ),
                    [
                        "alpha",
                        "bravo",
                        "charlie",
                    ].joined(
                        separator: "\n"
                    ),
                    "approved-preview.file-content"
                )
            }

            Step("reject stale approved preview on apply") {
                let workspace = try TestWorkspace(
                    "edit-constraints-stale-approved-preview"
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
                    operation: .replaceLineGuarded(
                        2,
                        expected: "beta",
                        with: "bravo"
                    ),
                    constraint: .bounded(
                        scope: .lines([
                            .init(
                                uncheckedStart: 2,
                                uncheckedEnd: 2
                            ),
                        ])
                    )
                )

                let preview = try editor.preview(
                    plan
                )

                try write(
                    [
                        "alpha",
                        "drifted",
                        "charlie",
                    ],
                    to: url
                )

                try expectApplyError(
                    .drift_detected,
                    "stale approved preview is rejected"
                ) {
                    _ = try editor.apply(
                        preview,
                        plan: plan
                    )
                }
            }

            Step("reject approved preview for different editor target") {
                let workspace = try TestWorkspace(
                    "edit-constraints-target-mismatch"
                )
                defer {
                    workspace.remove()
                }

                let sourceURL = workspace.file(
                    "source.txt"
                )
                let otherURL = workspace.file(
                    "other.txt"
                )

                try write(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: sourceURL
                )

                try write(
                    [
                        "alpha",
                        "beta",
                    ],
                    to: otherURL
                )

                let sourceEditor = StandardEditor(
                    sourceURL
                )
                let otherEditor = StandardEditor(
                    otherURL
                )

                let plan = try StandardEditPlan(
                    operation: .replaceLineGuarded(
                        2,
                        expected: "beta",
                        with: "bravo"
                    ),
                    constraint: .bounded(
                        scope: .lines([
                            .init(
                                uncheckedStart: 2,
                                uncheckedEnd: 2
                            ),
                        ])
                    )
                )

                let preview = try sourceEditor.preview(
                    plan
                )

                try expectApplyError(
                    .preview_target_mismatch,
                    "preview target mismatch is rejected"
                ) {
                    _ = try otherEditor.apply(
                        preview,
                        plan: plan
                    )
                }
            }

            Step("reject approved preview with mismatched operations") {
                let workspace = try TestWorkspace(
                    "edit-constraints-operation-mismatch"
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

                let originalPlan = try StandardEditPlan(
                    operation: .replaceLineGuarded(
                        2,
                        expected: "beta",
                        with: "bravo"
                    ),
                    constraint: .bounded(
                        scope: .lines([
                            .init(
                                uncheckedStart: 2,
                                uncheckedEnd: 2
                            ),
                        ])
                    )
                )

                let differentPlan = try StandardEditPlan(
                    operation: .replaceLineGuarded(
                        2,
                        expected: "beta",
                        with: "BETA"
                    ),
                    constraint: .bounded(
                        scope: .lines([
                            .init(
                                uncheckedStart: 2,
                                uncheckedEnd: 2
                            ),
                        ])
                    )
                )

                let preview = try editor.preview(
                    originalPlan
                )

                try expectApplyError(
                    .preview_operations_mismatch,
                    "preview operations mismatch is rejected"
                ) {
                    _ = try editor.apply(
                        preview,
                        plan: differentPlan
                    )
                }
            }

            Step("convenience edit still prepares and applies") {
                let workspace = try TestWorkspace(
                    "edit-constraints-convenience-edit"
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

                let plan = try StandardEditPlan(
                    operation: .replaceLineGuarded(
                        2,
                        expected: "beta",
                        with: "bravo"
                    ),
                    constraint: .bounded(
                        scope: .lines([
                            .init(
                                uncheckedStart: 2,
                                uncheckedEnd: 2
                            ),
                        ])
                    )
                )

                let result = try editor.edit(
                    plan
                )

                try Expect.equal(
                    result.performedWrite,
                    true,
                    "convenience-edit.performed-write"
                )

                try Expect.equal(
                    try read(
                        url
                    ),
                    [
                        "alpha",
                        "bravo",
                    ].joined(
                        separator: "\n"
                    ),
                    "convenience-edit.file-content"
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

private func expectViolation(
    _ expected: StandardEditViolationCode,
    _ label: String,
    operation: () throws -> Void
) throws {
    do {
        try operation()
    } catch let violation as StandardEditViolation {
        try Expect.equal(
            violation.code,
            expected,
            label
        )

        return
    } catch {
        throw TestFlowAssertionFailure(
            label: label,
            message: "unexpected error type",
            actual: String(
                describing: error
            ),
            expected: String(
                describing: expected
            )
        )
    }

    throw TestFlowAssertionFailure(
        label: label,
        message: "operation did not throw",
        actual: "completed",
        expected: String(
            describing: expected
        )
    )
}

private func expectApplyError(
    _ expected: StandardEditApplyErrorCode,
    _ label: String,
    operation: () throws -> Void
) throws {
    do {
        try operation()
    } catch let applyError as StandardEditApplyError {
        try Expect.equal(
            applyError.code,
            expected,
            label
        )

        return
    } catch {
        throw TestFlowAssertionFailure(
            label: label,
            message: "unexpected error type",
            actual: String(
                describing: error
            ),
            expected: String(
                describing: expected
            )
        )
    }

    throw TestFlowAssertionFailure(
        label: label,
        message: "operation did not throw",
        actual: "completed",
        expected: String(
            describing: expected
        )
    )
}
