import Foundation
import Testing

@main
enum WritersTestFlowsMain {
    static func main() async {
        let arguments = WritersTestArguments.parse(
            Array(
                CommandLine.arguments.dropFirst()
            )
        )

        let output = ClosureTestTextOutput { text in
            FileHandle.standardOutput.write(
                Data(
                    text.utf8
                )
            )
        }
        let reporter = PlainTextTestReporter(
            verbose: arguments.verbose,
            output: output
        )
        let result = await TestRunner.run(
            WritersFlowSuite.testSuite,
            configuration: .init(
                selection: .init(
                    names: arguments.names,
                    tags: arguments.tags,
                    skipTags: arguments.skipTags,
                    match: arguments.match
                ),
                failFast: arguments.failFast
            ),
            sink: reporter
        )

        Foundation.exit(
            result.isFailure ? 1 : 0
        )
    }
}

private struct WritersTestArguments {
    var names: [String] = []
    var tags: [String] = []
    var skipTags: [String] = []
    var match: [String] = []
    var failFast = false
    var verbose = false

    static func parse(
        _ rawArguments: [String]
    ) -> Self {
        var arguments = Self()
        var index = rawArguments.startIndex

        while index < rawArguments.endIndex {
            let argument = rawArguments[index]

            switch argument {
            case "--verbose":
                arguments.verbose = true
                index = rawArguments.index(
                    after: index
                )

            case "--fail-fast":
                arguments.failFast = true
                index = rawArguments.index(
                    after: index
                )

            case "--tag":
                index = consumeValue(
                    from: rawArguments,
                    after: index
                ) { value in
                    arguments.tags.append(
                        value
                    )
                }

            case "--skip-tag":
                index = consumeValue(
                    from: rawArguments,
                    after: index
                ) { value in
                    arguments.skipTags.append(
                        value
                    )
                }

            case "--match":
                index = consumeValue(
                    from: rawArguments,
                    after: index
                ) { value in
                    arguments.match.append(
                        value
                    )
                }

            default:
                arguments.names.append(
                    argument
                )
                index = rawArguments.index(
                    after: index
                )
            }
        }

        return arguments
    }

    private static func consumeValue(
        from rawArguments: [String],
        after index: Int,
        consume: (String) -> Void
    ) -> Int {
        let valueIndex = rawArguments.index(
            after: index
        )

        guard valueIndex < rawArguments.endIndex else {
            return valueIndex
        }

        consume(
            rawArguments[valueIndex]
        )

        return rawArguments.index(
            after: valueIndex
        )
    }
}
