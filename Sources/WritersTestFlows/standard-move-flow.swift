import Foundation
import TestFlows
import Writers

extension WritersFlowSuite {
    static var moveMutationFlow: TestFlow {
        TestFlow(
            "standard-move",
            tags: [
                "mutation",
                "move",
                "rollback",
                "drift",
                "workspace",
            ]
        ) {
            Step("move planning is side-effect free and rollback restores source") {
                let workspace = try TestWorkspace(
                    "standard-move-roundtrip"
                )
                defer {
                    workspace.remove()
                }

                let source = workspace.file(
                    "source.txt"
                )
                let destination = workspace.root
                    .appendingPathComponent(
                        "_archive/source.txt"
                    )

                try "fixture\n".write(
                    to: source,
                    atomically: true,
                    encoding: .utf8
                )

                let writer = MutationWriter()
                let plan = try writer.mutations.plan(
                    .move(
                        from: source,
                        to: destination
                    )
                )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: source.path
                    ),
                    "move.plan.source-preserved"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: destination.path
                    ),
                    "move.plan.destination-absent"
                )

                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "move.apply.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: source.path
                    ),
                    "move.apply.source-absent"
                )
                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: destination.path
                    ),
                    "move.apply.destination-present"
                )
                try Expect.equal(
                    try String(
                        contentsOf: destination,
                        encoding: .utf8
                    ),
                    "fixture\n",
                    "move.apply.content"
                )

                let rollback = try Expect.notNil(
                    result.rollback,
                    "move.rollback.plan"
                )
                let rollbackResult = writer.rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "move.rollback.status"
                )
                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: source.path
                    ),
                    "move.rollback.source-restored"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: destination.path
                    ),
                    "move.rollback.destination-absent"
                )
                try Expect.equal(
                    try String(
                        contentsOf: source,
                        encoding: .utf8
                    ),
                    "fixture\n",
                    "move.rollback.content"
                )
            }

            Step("move apply blocks stale source metadata") {
                let workspace = try TestWorkspace(
                    "standard-move-drift"
                )
                defer {
                    workspace.remove()
                }

                let source = workspace.file(
                    "source.txt"
                )
                let destination = workspace.file(
                    "destination.txt"
                )

                try "before\n".write(
                    to: source,
                    atomically: true,
                    encoding: .utf8
                )

                let writer = MutationWriter()
                let plan = try writer.mutations.plan(
                    .move(
                        from: source,
                        to: destination
                    )
                )

                try "changed after planning\n".write(
                    to: source,
                    atomically: true,
                    encoding: .utf8
                )

                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .failed,
                    "move.drift.status"
                )
                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: source.path
                    ),
                    "move.drift.source-preserved"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: destination.path
                    ),
                    "move.drift.destination-absent"
                )

                let failure = try Expect.notNil(
                    result.failed,
                    "move.drift.failure"
                )
                let planned = plan.entries[0]

                try Expect.equal(
                    failure.index,
                    planned.index,
                    "move.drift.failure-index"
                )
                try Expect.equal(
                    failure.entryID,
                    planned.id,
                    "move.drift.failure-entry"
                )
                try Expect.equal(
                    failure.target.standardizedFileURL,
                    source.standardizedFileURL,
                    "move.drift.failure-target"
                )
            }

            Step("directory move preserves nested contents and rollback restores tree") {
                let workspace = try TestWorkspace(
                    "standard-directory-move-roundtrip"
                )
                defer {
                    workspace.remove()
                }

                let source = workspace.root
                    .appendingPathComponent(
                        "source-directory",
                        isDirectory: true
                    )
                let nested = source
                    .appendingPathComponent(
                        "nested",
                        isDirectory: true
                    )
                let sourceFile = nested
                    .appendingPathComponent(
                        "fixture.txt"
                    )
                let destination = workspace.root
                    .appendingPathComponent(
                        "_archive/source-directory",
                        isDirectory: true
                    )
                let destinationFile = destination
                    .appendingPathComponent(
                        "nested/fixture.txt"
                    )

                try FileManager.default.createDirectory(
                    at: nested,
                    withIntermediateDirectories: true
                )
                try "directory fixture\n".write(
                    to: sourceFile,
                    atomically: true,
                    encoding: .utf8
                )

                let writer = MutationWriter()
                let plan = try writer.mutations.plan(
                    .move(
                        from: source,
                        to: destination
                    )
                )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: source.path
                    ),
                    "move.directory.plan.source-preserved"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: destination.path
                    ),
                    "move.directory.plan.destination-absent"
                )

                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "move.directory.apply.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: source.path
                    ),
                    "move.directory.apply.source-absent"
                )
                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: destinationFile.path
                    ),
                    "move.directory.apply.nested-file-present"
                )
                try Expect.equal(
                    try String(
                        contentsOf: destinationFile,
                        encoding: .utf8
                    ),
                    "directory fixture\n",
                    "move.directory.apply.nested-content"
                )

                let rollback = try Expect.notNil(
                    result.rollback,
                    "move.directory.rollback.plan"
                )
                let rollbackResult = writer.rollbacks.apply(
                    rollback
                )

                try Expect.equal(
                    rollbackResult.status,
                    .applied,
                    "move.directory.rollback.status"
                )
                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: sourceFile.path
                    ),
                    "move.directory.rollback.nested-file-restored"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: destination.path
                    ),
                    "move.directory.rollback.destination-absent"
                )
                try Expect.equal(
                    try String(
                        contentsOf: sourceFile,
                        encoding: .utf8
                    ),
                    "directory fixture\n",
                    "move.directory.rollback.nested-content"
                )
            }

            Step("move rejects symbolic-link sources") {
                let workspace = try TestWorkspace(
                    "standard-move-symlink"
                )
                defer {
                    workspace.remove()
                }

                let target = workspace.file(
                    "target.txt"
                )
                let source = workspace.root
                    .appendingPathComponent(
                        "source-link"
                    )
                let destination = workspace.root
                    .appendingPathComponent(
                        "destination-link"
                    )

                try "symlink fixture\n".write(
                    to: target,
                    atomically: true,
                    encoding: .utf8
                )
                try FileManager.default.createSymbolicLink(
                    at: source,
                    withDestinationURL: target
                )

                try Expect.throwsError(
                    "move.symlink.rejected"
                ) {
                    _ = try MutationWriter().mutations.plan(
                        .move(
                            from: source,
                            to: destination
                        )
                    )
                }

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: source.path
                    ),
                    "move.symlink.source-preserved"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: destination.path
                    ),
                    "move.symlink.destination-absent"
                )
            }

            Step("WorkspaceWriter move resolves both paths") {
                let workspace = try TestWorkspace(
                    "workspace-move"
                )
                defer {
                    workspace.remove()
                }

                let source = workspace.file(
                    "source.txt"
                )
                let destination = workspace.root
                    .appendingPathComponent(
                        "nested/archive.txt"
                    )

                try "workspace fixture\n".write(
                    to: source,
                    atomically: true,
                    encoding: .utf8
                )

                let writer = try WorkspaceWriter(
                    root: workspace.root
                )
                let plan = try writer.mutations.plan(
                    .move(
                        from: "source.txt",
                        to: "nested/archive.txt"
                    )
                )
                let result = writer.mutations.apply(
                    plan
                )

                try Expect.equal(
                    result.status,
                    .applied,
                    "workspace.move.status"
                )
                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: source.path
                    ),
                    "workspace.move.source-absent"
                )
                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: destination.path
                    ),
                    "workspace.move.destination-present"
                )
                try Expect.equal(
                    try String(
                        contentsOf: destination,
                        encoding: .utf8
                    ),
                    "workspace fixture\n",
                    "workspace.move.content"
                )
            }
        }
    }
}
