import TestFlows

@main
enum WritersTestFlowsMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: WritersFlowSuite.self
        )
    }
}
