import Position
import Testing
import Writers

extension WritersFlowSuite {
    static var positionRangeEditFlow: TestFlow {
        TestFlow(
            "position-range-edit",
            tags: [
                "edit",
                "position",
                "range",
                "snapshot",
            ]
        ) {
            Step("replace half-open character range") {
                let range = PositionRange(
                    uncheckedStart: .init(6),
                    uncheckedEnd: .init(10)
                )

                try Expect.equal(
                    try StandardEditOperation.text.replace(
                        range,
                        with: "bravo"
                    ).applying(
                        to: "alpha beta gamma"
                    ),
                    "alpha bravo gamma",
                    "position-range.basic"
                )
            }

            Step("guarded replacement validates exact content") {
                let range = PositionRange(
                    uncheckedStart: .init(6),
                    uncheckedEnd: .init(10)
                )

                try Expect.equal(
                    try StandardEditOperation.text.replace(
                        range,
                        expected: "beta",
                        with: "bravo"
                    ).applying(
                        to: "alpha beta gamma"
                    ),
                    "alpha bravo gamma",
                    "position-range.guarded"
                )

                try Expect.throwsError(
                    "position-range.guard-mismatch"
                ) {
                    _ = try StandardEditOperation.text.replace(
                        range,
                        expected: "wrong",
                        with: "bravo"
                    ).applying(
                        to: "alpha beta gamma"
                    )
                }
            }

            Step("character offsets preserve extended grapheme clusters") {
                try Expect.equal(
                    try StandardEditOperation.text.replace(
                        PositionRange(
                            uncheckedStart: .init(1),
                            uncheckedEnd: .init(2)
                        ),
                        with: "dog"
                    ).applying(
                        to: "a🐕b"
                    ),
                    "adogb",
                    "position-range.character-offset"
                )
            }

            Step("empty and out-of-bounds ranges are rejected") {
                try Expect.throwsError(
                    "position-range.empty"
                ) {
                    _ = try StandardEditOperation.text.replace(
                        .point(1),
                        with: "x"
                    ).applying(
                        to: "abc"
                    )
                }

                try Expect.throwsError(
                    "position-range.out-of-bounds"
                ) {
                    _ = try StandardEditOperation.text.replace(
                        PositionRange(
                            uncheckedStart: .init(1),
                            uncheckedEnd: .init(9)
                        ),
                        with: "x"
                    ).applying(
                        to: "abc"
                    )
                }
            }

            Step("snapshot ranges retain original coordinates") {
                let content = "0123456789ABCDEFGHIJ"

                let grown = try StandardEditOperation.applyingSnapshot(
                    [
                        .replaceRange(
                            PositionRange(
                                uncheckedStart: .init(2),
                                uncheckedEnd: .init(4)
                            ),
                            with: "LONG"
                        ),
                        .replaceRangeGuarded(
                            PositionRange(
                                uncheckedStart: .init(12),
                                uncheckedEnd: .init(14)
                            ),
                            expected: "CD",
                            with: "zz"
                        ),
                    ],
                    to: content
                )

                try Expect.equal(
                    grown,
                    "01LONG456789ABzzEFGHIJ",
                    "position-range.snapshot-grow"
                )

                let shrunk = try StandardEditOperation.applyingSnapshot(
                    [
                        .replaceRange(
                            PositionRange(
                                uncheckedStart: .init(2),
                                uncheckedEnd: .init(6)
                            ),
                            with: "x"
                        ),
                        .replaceRangeGuarded(
                            PositionRange(
                                uncheckedStart: .init(12),
                                uncheckedEnd: .init(14)
                            ),
                            expected: "CD",
                            with: "zz"
                        ),
                    ],
                    to: content
                )

                try Expect.equal(
                    shrunk,
                    "01x6789ABzzEFGHIJ",
                    "position-range.snapshot-shrink"
                )
            }

            Step("snapshot rejects overlap and mixed coordinate families") {
                try Expect.throwsError(
                    "position-range.snapshot-overlap"
                ) {
                    _ = try StandardEditOperation.applyingSnapshot(
                        [
                            .replaceRange(
                                PositionRange(
                                    uncheckedStart: .init(2),
                                    uncheckedEnd: .init(5)
                                ),
                                with: "x"
                            ),
                            .replaceRange(
                                PositionRange(
                                    uncheckedStart: .init(4),
                                    uncheckedEnd: .init(7)
                                ),
                                with: "y"
                            ),
                        ],
                        to: "0123456789"
                    )
                }

                try Expect.throwsError(
                    "position-range.snapshot-mixed"
                ) {
                    _ = try StandardEditOperation.applyingSnapshot(
                        [
                            .replaceRange(
                                PositionRange(
                                    uncheckedStart: .init(0),
                                    uncheckedEnd: .init(1)
                                ),
                                with: "x"
                            ),
                            .replaceLine(
                                1,
                                with: "line"
                            ),
                        ],
                        to: "abc"
                    )
                }
            }

            Step("existing-content guard policy recognizes range guards") {
                let constraint = StandardEditConstraint(
                    operations: .precise,
                    guards: .existingLines
                )
                let range = PositionRange(
                    uncheckedStart: .init(0),
                    uncheckedEnd: .init(1)
                )

                try constraint.validate(
                    .replaceRangeGuarded(
                        range,
                        expected: "a",
                        with: "b"
                    ),
                    operationIndex: 1
                )

                try Expect.throwsError(
                    "position-range.guard-required"
                ) {
                    try constraint.validate(
                        .replaceRange(
                            range,
                            with: "b"
                        ),
                        operationIndex: 1
                    )
                }
            }
        }
    }
}
