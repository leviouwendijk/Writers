import Foundation
import Path
import TestFlows
import Writers

extension WritersFlowSuite {
    static var workspaceWriterFlow: TestFlow {
        TestFlow(
            "workspace-writer",
            tags: [
                "workspace",
                "path",
                "policy",
                "mutation",
            ]
        ) {
            Step("file writer resolves allowed relative path") {
                let workspace = try TestWorkspace(
                    "workspace-writer-file"
                )
                defer {
                    workspace.remove()
                }

                let root = workspace.root
                let writer = try WorkspaceWriter(
                    root: root
                )

                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(
                        "Sources/App"
                    ),
                    withIntermediateDirectories: true
                )

                let file = try writer.file(
                    "Sources/App/main.swift"
                )

                try file.write(
                    "print(\"hello\")\n"
                )

                try Expect.equal(
                    try workspaceRead(
                        root.appendingPathComponent(
                            "Sources/App/main.swift"
                        )
                    ),
                    "print(\"hello\")\n",
                    "workspace.file.content"
                )
            }

            Step("default policy blocks .env") {
                let workspace = try TestWorkspace(
                    "workspace-writer-env-denied"
                )
                defer {
                    workspace.remove()
                }

                let writer = try WorkspaceWriter(
                    root: workspace.root
                )

                try Expect.throwsError(
                    "workspace.env-denied"
                ) {
                    _ = try writer.file(
                        ".env"
                    )
                }
            }

            Step("default policy blocks .agentic") {
                let workspace = try TestWorkspace(
                    "workspace-writer-agentic-denied"
                )
                defer {
                    workspace.remove()
                }

                let writer = try WorkspaceWriter(
                    root: workspace.root
                )

                try Expect.throwsError(
                    "workspace.agentic-denied"
                ) {
                    _ = try writer.file(
                        ".agentic/state.json"
                    )
                }
            }

            Step("path escape is rejected") {
                let workspace = try TestWorkspace(
                    "workspace-writer-escape"
                )
                defer {
                    workspace.remove()
                }

                let writer = try WorkspaceWriter(
                    root: workspace.root
                )

                try Expect.throwsError(
                    "workspace.escape-denied"
                ) {
                    _ = try writer.file(
                        "../outside.txt"
                    )
                }
            }

            Step("mutation create resolves raw path through workspace") {
                let workspace = try TestWorkspace(
                    "workspace-writer-create"
                )
                defer {
                    workspace.remove()
                }

                let root = workspace.root
                let writer = try WorkspaceWriter(
                    root: root
                )

                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(
                        "Sources"
                    ),
                    withIntermediateDirectories: true
                )

                let plan = try writer.mutations.plan(
                    .createText(
                        at: "Sources/generated.swift",
                        content: "public struct Generated {}\n"
                    )
                )
                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "workspace.create.status"
                )
                try Expect.equal(
                    try workspaceRead(
                        root.appendingPathComponent(
                            "Sources/generated.swift"
                        )
                    ),
                    "public struct Generated {}\n",
                    "workspace.create.content"
                )
            }

            Step("mutation edit resolves raw path through workspace") {
                let workspace = try TestWorkspace(
                    "workspace-writer-edit"
                )
                defer {
                    workspace.remove()
                }

                let root = workspace.root
                let target = root.appendingPathComponent(
                    "Sources/edit.swift"
                )

                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(
                        "Sources"
                    ),
                    withIntermediateDirectories: true
                )
                try "one\ntwo".write(
                    to: target,
                    atomically: true,
                    encoding: .utf8
                )

                let writer = try WorkspaceWriter(
                    root: root
                )
                let plan = try writer.mutations.plan(
                    .editText(
                        at: "Sources/edit.swift",
                        operations: [
                            .replaceLineGuarded(
                                2,
                                expected: "two",
                                with: "TWO"
                            ),
                        ]
                    )
                )
                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "workspace.edit.status"
                )
                try Expect.equal(
                    try workspaceRead(
                        target
                    ),
                    "one\nTWO",
                    "workspace.edit.content"
                )
            }

            Step("mutation rollback works through workspace") {
                let workspace = try TestWorkspace(
                    "workspace-writer-rollback"
                )
                defer {
                    workspace.remove()
                }

                let root = workspace.root
                let writer = try WorkspaceWriter(
                    root: root
                )

                let plan = try writer.mutations.plan(
                    .createText(
                        at: "created.txt",
                        content: "created\n"
                    )
                )
                let result = writer.mutations.apply(
                    plan
                )
                let rollback = try Expect.notNil(
                    result.rollback,
                    "workspace.rollback.plan"
                )

                let rollbackResult = writer.mutations.rollback(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "workspace.rollback.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: root.appendingPathComponent(
                            "created.txt"
                        ).path
                    ),
                    "workspace.rollback.deleted"
                )
            }

            Step("multi-root root identifier selects intended root") {
                let workspace = try TestWorkspace(
                    "workspace-writer-multiroot"
                )
                defer {
                    workspace.remove()
                }

                let first = workspace.root.appendingPathComponent(
                    "first"
                )
                let second = workspace.root.appendingPathComponent(
                    "second"
                )

                try FileManager.default.createDirectory(
                    at: first,
                    withIntermediateDirectories: true
                )
                try FileManager.default.createDirectory(
                    at: second,
                    withIntermediateDirectories: true
                )

                let access = try PathAccessController(
                    roots: [
                        .init(
                            id: "first",
                            label: "First",
                            scope: .init(
                                root: first
                            ),
                            isDefault: true
                        ),
                        .init(
                            id: "second",
                            label: "Second",
                            scope: .init(
                                root: second
                            )
                        ),
                    ],
                    defaultRootIdentifier: "first"
                )

                let writer = WorkspaceWriter(
                    access: access
                )
                let plan = try writer.mutations.plan(
                    .createText(
                        at: "selected.txt",
                        rootIdentifier: "second",
                        content: "second\n"
                    )
                )
                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "workspace.multiroot.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: first.appendingPathComponent(
                            "selected.txt"
                        ).path
                    ),
                    "workspace.multiroot.first-missing"
                )
                try Expect.equal(
                    try workspaceRead(
                        second.appendingPathComponent(
                            "selected.txt"
                        )
                    ),
                    "second\n",
                    "workspace.multiroot.second-content"
                )
            }

            Step("create_text rejects existing file") {
                let workspace = try TestWorkspace(
                    "workspace-writer-create-existing"
                )
                defer {
                    workspace.remove()
                }

                let root = workspace.root
                let target = root.appendingPathComponent(
                    "existing.txt"
                )

                try "already\n".write(
                    to: target,
                    atomically: true,
                    encoding: .utf8
                )

                let writer = try WorkspaceWriter(
                    root: root
                )

                try Expect.throwsError(
                    "workspace.create-existing-rejected"
                ) {
                    _ = try writer.mutations.plan(
                        .createText(
                            at: "existing.txt",
                            content: "new\n"
                        )
                    )
                }
            }

            Step("replace_text upsert remains the overwrite/create path") {
                let workspace = try TestWorkspace(
                    "workspace-writer-replace-upsert"
                )
                defer {
                    workspace.remove()
                }

                let root = workspace.root
                let writer = try WorkspaceWriter(
                    root: root
                )

                let plan = try writer.mutations.plan(
                    .replaceText(
                        at: "upsert.txt",
                        content: "upsert\n",
                        policy: .upsert
                    )
                )
                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "workspace.upsert.status"
                )
                try Expect.equal(
                    try workspaceRead(
                        root.appendingPathComponent(
                            "upsert.txt"
                        )
                    ),
                    "upsert\n",
                    "workspace.upsert.content"
                )
            }
        }
    }
}

private func workspaceRead(
    _ url: URL
) throws -> String {
    try String(
        contentsOf: url,
        encoding: .utf8
    )
}
