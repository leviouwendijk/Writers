import Foundation
import TestFlows
import Writers

extension WritersFlowSuite {
    static var writerFacadeFlow: TestFlow {
        TestFlow(
            "writer-facades",
            tags: [
                "writer",
                "facade",
                "mutation",
            ]
        ) {
            Step("FileWriter is the nominal single-file writer") {
                let workspace = try TestWorkspace(
                    "writer-facade-file-writer"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "file.txt"
                )
                let writer = FileWriter(
                    target
                )

                try writer.write(
                    "alpha\n"
                )

                try Expect.equal(
                    try facadeRead(
                        target
                    ),
                    "alpha\n",
                    "file-writer.content"
                )
            }

            Step("SafeFile and StandardWriter remain compatibility aliases") {
                let workspace = try TestWorkspace(
                    "writer-facade-aliases"
                )
                defer {
                    workspace.remove()
                }

                let safeTarget = workspace.file(
                    "safe.txt"
                )
                let standardTarget = workspace.file(
                    "standard.txt"
                )

                let safe = SafeFile(
                    safeTarget
                )
                let standard = StandardWriter(
                    standardTarget
                )

                try safe.write(
                    "safe\n"
                )
                try standard.write(
                    "standard\n"
                )

                try Expect.equal(
                    try facadeRead(
                        safeTarget
                    ),
                    "safe\n",
                    "safe-file.content"
                )
                try Expect.equal(
                    try facadeRead(
                        standardTarget
                    ),
                    "standard\n",
                    "standard-writer.content"
                )
            }

            Step("MutationWriter plans and applies multi-file mutations") {
                let workspace = try TestWorkspace(
                    "writer-facade-mutation-writer"
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

                let writer = MutationWriter()
                let plan = try writer.mutations.plan([
                    .createText(
                        at: first,
                        content: "first\n"
                    ),
                    .createText(
                        at: second,
                        content: "second\n"
                    ),
                ])
                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "mutation-writer.status"
                )
                try Expect.equal(
                    try facadeRead(
                        first
                    ),
                    "first\n",
                    "mutation-writer.first"
                )
                try Expect.equal(
                    try facadeRead(
                        second
                    ),
                    "second\n",
                    "mutation-writer.second"
                )
            }

            Step("MutationWriter rollback applies pass rollback") {
                let workspace = try TestWorkspace(
                    "writer-facade-mutation-rollback"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "created.txt"
                )

                let writer = MutationWriter()
                let plan = try writer.mutations.plan(
                    .createText(
                        at: target,
                        content: "created\n"
                    )
                )
                let result = writer.mutations.apply(
                    plan
                )
                let rollback = try Expect.notNil(
                    result.rollback,
                    "mutation-writer.rollback"
                )

                let rollbackResult = writer.rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "mutation-writer.rollback.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: target.path
                    ),
                    "mutation-writer.rollback.deleted"
                )
            }

            Step("WorkspaceWriter resolves relative files through path access") {
                let workspace = try TestWorkspace(
                    "writer-facade-workspace-placeholder"
                )
                defer {
                    workspace.remove()
                }

                let root = workspace.root
                let writer = try WorkspaceWriter(
                    root: root
                )
                let file = try writer.file(
                    "nested/file.txt"
                )

                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(
                        "nested"
                    ),
                    withIntermediateDirectories: true
                )

                try file.write(
                    "workspace\n"
                )

                try Expect.equal(
                    try facadeRead(
                        root.appendingPathComponent(
                            "nested/file.txt"
                        )
                    ),
                    "workspace\n",
                    "workspace-writer.content"
                )
            }
        }
    }
}

private func facadeRead(
    _ url: URL
) throws -> String {
    try String(
        contentsOf: url,
        encoding: .utf8
    )
}
