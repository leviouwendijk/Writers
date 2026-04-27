import Position
import TestFlows
import Writers

extension WritersFlowSuite {
    static var editLinePayloadShapeFlow: TestFlow {
        TestFlow(
            "edit-line-payload-shape",
            tags: [
                "edit",
                "line",
                "validation",
                "shape",
            ]
        ) {
            Step("line-oriented operations reject embedded newlines") {
                try expectLinePayloadNewlineViolation(
                    "replace-line.content"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLine(
                            1,
                            with: "alpha\nbeta"
                        ),
                        constraint: .unrestricted
                    )
                }

                try expectLinePayloadNewlineViolation(
                    "replace-line-guarded.expected"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLineGuarded(
                            1,
                            expected: "alpha\nbeta",
                            with: "gamma"
                        ),
                        constraint: .unrestricted
                    )
                }

                try expectLinePayloadNewlineViolation(
                    "replace-line-guarded.content"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLineGuarded(
                            1,
                            expected: "alpha",
                            with: "beta\ngamma"
                        ),
                        constraint: .unrestricted
                    )
                }

                try expectLinePayloadNewlineViolation(
                    "insert-lines.lines"
                ) {
                    _ = try StandardEditPlan(
                        operation: .insertLines(
                            [
                                "alpha\nbeta",
                            ],
                            atLine: 1
                        ),
                        constraint: .unrestricted
                    )
                }

                try expectLinePayloadNewlineViolation(
                    "replace-lines.lines"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLines(
                            LineRange(
                                uncheckedStart: 1,
                                uncheckedEnd: 1
                            ),
                            with: [
                                "alpha\nbeta",
                            ]
                        ),
                        constraint: .unrestricted
                    )
                }

                try expectLinePayloadNewlineViolation(
                    "replace-lines-guarded.expected"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLinesGuarded(
                            LineRange(
                                uncheckedStart: 1,
                                uncheckedEnd: 1
                            ),
                            expected: [
                                "alpha\nbeta",
                            ],
                            with: [
                                "gamma",
                            ]
                        ),
                        constraint: .unrestricted
                    )
                }

                try expectLinePayloadNewlineViolation(
                    "replace-lines-guarded.lines"
                ) {
                    _ = try StandardEditPlan(
                        operation: .replaceLinesGuarded(
                            LineRange(
                                uncheckedStart: 1,
                                uncheckedEnd: 1
                            ),
                            expected: [
                                "alpha",
                            ],
                            with: [
                                "beta\ngamma",
                            ]
                        ),
                        constraint: .unrestricted
                    )
                }

                try expectLinePayloadNewlineViolation(
                    "delete-lines-guarded.expected"
                ) {
                    _ = try StandardEditPlan(
                        operation: .deleteLinesGuarded(
                            LineRange(
                                uncheckedStart: 1,
                                uncheckedEnd: 1
                            ),
                            expected: [
                                "alpha\nbeta",
                            ]
                        ),
                        constraint: .unrestricted
                    )
                }
            }

            Step("line-oriented operations accept separate line items") {
                _ = try StandardEditPlan(
                    operations: [
                        .insertLines(
                            [
                                "alpha",
                                "beta",
                                "gamma",
                            ],
                            atLine: 1
                        ),
                        .replaceLines(
                            LineRange(
                                uncheckedStart: 1,
                                uncheckedEnd: 2
                            ),
                            with: [
                                "delta",
                                "epsilon",
                            ]
                        ),
                    ],
                    constraint: .unrestricted
                )
            }

            Step("wide text operations still allow multiline payloads") {
                _ = try StandardEditPlan(
                    operations: [
                        .append(
                            "alpha\nbeta",
                            separator: "\n"
                        ),
                        .replaceEntireFile(
                            with: "gamma\ndelta\n"
                        ),
                    ],
                    constraint: .unrestricted
                )
            }
        }
    }
}

private func expectLinePayloadNewlineViolation(
    _ label: String,
    _ body: () throws -> Void
) throws {
    do {
        try body()
    } catch let violation as StandardEditViolation {
        try Expect.equal(
            violation.code,
            .line_payload_contains_newline,
            "\(label).violation-code"
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
                describing: StandardEditViolationCode.line_payload_contains_newline
            )
        )
    }

    throw TestFlowAssertionFailure(
        label: label,
        message: "operation did not throw",
        actual: "completed",
        expected: String(
            describing: StandardEditViolationCode.line_payload_contains_newline
        )
    )
}
