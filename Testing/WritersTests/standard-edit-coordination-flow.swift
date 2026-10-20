import Foundation
import Position
import Testing
import Writers

extension WritersFlowSuite {
    static var coordinatedEditFlow: TestFlow {
        TestFlow(
            "coordinated-edit",
            tags: ["edit", "concurrency", "provenance"]
        ) {
            Step("independent files, first-acquirer conflicts, retained proposals, and typed construction") {
                let workspace = try TestWorkspace("coordinated-edit")
                defer { workspace.remove() }

                let first = workspace.file("first.swift")
                let second = workspace.file("second.swift")
                _ = try StandardWriter(first).write(
                    "one\ntwo\nthree\nfour\n",
                    options: .overwriteWithoutBackup
                )
                _ = try StandardWriter(second).write(
                    "uno\ndos\n",
                    options: .overwriteWithoutBackup
                )

                let coordinator = StandardEditCoordinator()
                _ = try await coordinator.read([first, second])
                let alpha = try await coordinator.mutator(name: "alpha")
                let beta = try await coordinator.mutator(name: "beta")

                let row_two = LineRange(uncheckedStart: 2, uncheckedEnd: 2)
                let first_winner = try await alpha.acquire(
                    file: first,
                    scope: .lines([row_two])
                )
                let first_loser = try await beta.acquire(
                    file: first,
                    scope: .lines([row_two])
                )
                let second_winner = try await beta.acquire(
                    file: second,
                    scope: .lines([row_two])
                )
                let insertion = try await alpha.acquire(
                    file: first,
                    scope: .insertions([1])
                )

                guard case .granted = first_winner.state,
                      case .contested = first_loser.state,
                      case .granted = second_winner.state else {
                    throw StandardEditCoordinationError.invalid_phase
                }

                let accepted = try await alpha.submit(
                    acquisition: first_winner,
                    operation: .replaceLineGuarded(2, expected: "two", with: "TWO"),
                    comment: "normalize first branch"
                )
                let excluded = try await beta.submit(
                    acquisition: first_loser,
                    operation: .replaceLineGuarded(2, expected: "two", with: "OTHER"),
                    comment: "alternative expected behavior for reconciliation"
                )
                _ = try await beta.submit(
                    acquisition: second_winner,
                    operation: .replaceLineGuarded(2, expected: "dos", with: "DOS")
                )
                _ = try await alpha.submit(
                    acquisition: insertion,
                    operation: .insertLines(["header"], atLine: 1)
                )

                let provisional = try await coordinator.construct()
                let first_preview = try Expect.notNil(
                    provisional.files.first(where: { $0.file == first.standardizedFileURL.resolvingSymlinksInPath() }),
                    "coordinated.file.preview"
                )
                try Expect.equal(
                    String(decoding: first_preview.materialize(source_bytes: Data(contentsOf: first)), as: UTF8.self),
                    "header\none\nTWO\nthree\nfour\n",
                    "coordinated.preview.materialization"
                )

                try await alpha.stop()
                try await coordinator.seal()
                do {
                    _ = try await coordinator.write(provisional, options: .overwriteWithoutBackup)
                    throw StandardEditCoordinationError.invalid_phase
                } catch StandardEditCoordinationError.active_mutators {
                    // A stopped mutator does not imply every connection has stopped.
                }
                try await beta.stop()
                let construction = try await coordinator.construct()
                let commit = try await coordinator.write(
                    construction,
                    options: .overwriteWithoutBackup
                )
                try Expect.equal(
                    try workspace.read(first),
                    "header\none\nTWO\nthree\nfour\n",
                    "coordinated.first.file"
                )
                try Expect.equal(
                    try workspace.read(second),
                    "uno\nDOS\n",
                    "coordinated.second.file"
                )
                try Expect.equal(commit.files.count, 2, "coordinated.files.written")

                let losing_record = try Expect.notNil(
                    commit.mutations.first(where: { $0.id == excluded.id }),
                    "coordinated.excluded.mutation"
                )
                guard case .contested = losing_record.state else {
                    throw StandardEditCoordinationError.invalid_phase
                }
                try Expect.equal(
                    losing_record.comment,
                    "alternative expected behavior for reconciliation",
                    "coordinated.excluded.reason"
                )
                let winning_record = try Expect.notNil(
                    commit.mutations.first(where: { $0.id == accepted.id }),
                    "coordinated.applied.mutation"
                )
                guard case .committed = winning_record.state else {
                    throw StandardEditCoordinationError.invalid_phase
                }
            }

            Step("coordinated operation boundary excludes unsupported text operations") {
                let supported = try StandardCoordinatedEditOperation(
                    .replaceLine(1, with: "replacement")
                )
                try Expect.equal(
                    supported.standard_operation,
                    .replaceLine(1, with: "replacement"),
                    "coordinated.typed_round_trip"
                )
                var rejected = false
                do {
                    _ = try StandardCoordinatedEditOperation(.append("unsupported"))
                } catch StandardEditCoordinationError.unsupported_operation {
                    rejected = true
                }
                try Expect.true(rejected, "coordinated.unsupported_operation_rejected_at_boundary")
            }

            Step("withdrawal retains an explanation and excludes content") {
                let workspace = try TestWorkspace("coordinated-withdraw")
                defer { workspace.remove() }
                let url = workspace.file("sample.txt")
                _ = try StandardWriter(url).write("alpha\nbeta\n", options: .overwriteWithoutBackup)
                let coordinator = StandardEditCoordinator()
                _ = try await coordinator.read([url])
                let worker = try await coordinator.mutator(name: "sole-mutator")
                let lease = try await worker.acquire(
                    file: url,
                    scope: .lines([.init(uncheckedStart: 1, uncheckedEnd: 1)])
                )
                let submitted = try await worker.submit(
                    acquisition: lease,
                    operation: .replaceLineGuarded(1, expected: "alpha", with: "ALPHA")
                )
                try await coordinator.withdraw(
                    mutation_id: submitted.id,
                    comment: "would introduce incompatible behavior"
                )
                try await worker.stop()
                try await coordinator.seal()
                let construction = try await coordinator.construct()
                let commit = try await coordinator.write(construction, options: .overwriteWithoutBackup)
                try Expect.equal(commit.files.count, 0, "coordinated.no_unnecessary_write")
                try Expect.equal(try workspace.read(url), "alpha\nbeta\n", "coordinated.withdraw.unchanged")
                let record = try Expect.notNil(commit.mutations.first, "coordinated.withdraw.record")
                guard case .withdrawn(let reason) = record.state else {
                    throw StandardEditCoordinationError.invalid_phase
                }
                try Expect.equal(reason, "would introduce incompatible behavior", "coordinated.withdraw.reason")
            }

            Step("stale disk content blocks publication") {
                let workspace = try TestWorkspace("coordinated-drift")
                defer { workspace.remove() }
                let url = workspace.file("sample.txt")
                _ = try StandardWriter(url).write("first\n", options: .overwriteWithoutBackup)
                let coordinator = StandardEditCoordinator()
                _ = try await coordinator.read([url])
                let worker = try await coordinator.mutator(name: "drift-worker")
                let lease = try await worker.acquire(file: url, scope: .file)
                _ = try await worker.submit(
                    acquisition: lease,
                    operation: .replaceLineGuarded(1, expected: "first", with: "second")
                )
                try await worker.stop()
                try await coordinator.seal()
                let construction = try await coordinator.construct()
                _ = try StandardWriter(url).write("external\n", options: .overwriteWithoutBackup)
                do {
                    _ = try await coordinator.write(construction, options: .overwriteWithoutBackup)
                    throw StandardEditCoordinationError.invalid_phase
                } catch StandardEditCoordinationError.external_change {
                    // External drift must not be overwritten.
                }
                try Expect.equal(try workspace.read(url), "external\n", "coordinated.drift.preserved")
            }
        }
    }
}
