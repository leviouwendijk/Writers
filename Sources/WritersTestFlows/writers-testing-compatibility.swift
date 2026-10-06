import Foundation
import Testing

struct WritersTestStep: Sendable {
    let name: String
    private let operation: @Sendable () async throws -> Void

    init(
        name: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        self.name = name
        self.operation = operation
    }

    func run() async throws {
        try await operation()
    }
}

@resultBuilder
enum WritersTestStepBuilder {
    static func buildBlock(
        _ components: [WritersTestStep]...
    ) -> [WritersTestStep] {
        components.flatMap { $0 }
    }

    static func buildExpression(
        _ expression: WritersTestStep
    ) -> [WritersTestStep] {
        [expression]
    }

    static func buildExpression(
        _ expression: [WritersTestStep]
    ) -> [WritersTestStep] {
        expression
    }

    static func buildOptional(
        _ component: [WritersTestStep]?
    ) -> [WritersTestStep] {
        component ?? []
    }

    static func buildEither(
        first component: [WritersTestStep]
    ) -> [WritersTestStep] {
        component
    }

    static func buildEither(
        second component: [WritersTestStep]
    ) -> [WritersTestStep] {
        component
    }

    static func buildArray(
        _ components: [[WritersTestStep]]
    ) -> [WritersTestStep] {
        components.flatMap { $0 }
    }
}

func Step(
    _ name: String,
    _ operation: @escaping @Sendable () throws -> Void
) -> WritersTestStep {
    WritersTestStep(
        name: name
    ) {
        try operation()
    }
}

func Step(
    _ name: String,
    _ operation: @escaping @Sendable () async throws -> Void
) -> WritersTestStep {
    WritersTestStep(
        name: name,
        operation: operation
    )
}

extension TestFlow {
    init(
        _ id: String,
        title: String? = nil,
        tags: Set<String> = [],
        @WritersTestStepBuilder steps: () -> [WritersTestStep]
    ) {
        let steps = steps()

        self.init(
            id: id,
            title: title,
            tags: tags
        ) {
            let startedAt = Date()
            var results: [TestFlowActionResult] = []

            for step in steps {
                let stepStartedAt = Date()

                do {
                    try await step.run()

                    results.append(
                        .pass(
                            name: step.name,
                            kind: .step,
                            startedAt: stepStartedAt,
                            endedAt: Date()
                        )
                    )
                } catch {
                    let diagnostics = TestErrorDiagnostics.diagnostics(
                        for: error
                    )

                    results.append(
                        .fail(
                            name: step.name,
                            kind: .step,
                            startedAt: stepStartedAt,
                            endedAt: Date(),
                            diagnostics: diagnostics
                        )
                    )

                    return .failed(
                        name: id,
                        startedAt: startedAt,
                        endedAt: Date(),
                        diagnostics: [
                            .field(
                                "failed_action",
                                step.name
                            ),
                            .field(
                                "failed_action_kind",
                                TestFlowActionKind.step.rawValue
                            ),
                        ] + diagnostics,
                        steps: results
                    )
                }
            }

            return .passed(
                name: id,
                startedAt: startedAt,
                endedAt: Date(),
                steps: results
            )
        }
    }
}

extension Expect {
    static func snapshot(
        _ actual: String,
        named name: String
    ) throws {
        let url = URL(
            fileURLWithPath: ".testflows/snapshots",
            isDirectory: true
        ).appendingPathComponent(
            "\(name).snap",
            isDirectory: false
        )

        let expected = try String(
            contentsOf: url,
            encoding: .utf8
        )

        try equal(
            actual,
            expected,
            "snapshot.\(name)"
        )
    }
}
