import Foundation
import Testing
import Writers

extension WritersFlowSuite {
    static var coordinatedMutationFlow: TestFlow {
        TestFlow("coordinated-mutations", tags: ["mutations", "concurrency", "rollback"]) {
            Step("disjoint edits use one mutation application, then accept a new round") {
                let workspace = try TestWorkspace("mutation-coordination-rounds")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("one\ntwo\nthree\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let first = await coordinator.participant(name: "session-A")
                let second = await coordinator.participant(name: "session-B")
                let a = try await first.submit(.editText(
                    at: file,
                    operations: [.replaceLineGuarded(1, expected: "one", with: "ONE")]
                ))
                _ = try await second.submit(.editText(
                    at: file,
                    operations: [.replaceLineGuarded(3, expected: "three", with: "THREE")]
                ))
                try Expect.equal(try workspace.read(file), "one\ntwo\nthree\n", "staged.off_disk")
                let published = try Expect.notNil(
                    try await coordinator.publish(), "mutation.first_publication"
                )
                try Expect.equal(published.result.status, .applied, "mutation.status")
                try Expect.equal(published.result.records.count, 1, "mutation.unified_record")
                try Expect.equal(try workspace.read(file), "ONE\ntwo\nTHREE\n", "mutation.combined")
                let journal = await coordinator.journal()
                let committed = try Expect.notNil(journal.first(where: { $0.id == a.id }), "mutation.journal")
                guard case .committed = committed.state else {
                    throw StandardMutationCoordinationError.submission_not_pending(a.id)
                }
                _ = try await first.submit(.editText(
                    at: file,
                    operations: [.replaceLineGuarded(2, expected: "two", with: "TWO")]
                ))
                let again = try Expect.notNil(try await coordinator.publish(), "mutation.second_publication")
                try Expect.equal(again.result.status, .applied, "mutation.second_status")
                try Expect.equal(try workspace.read(file), "ONE\nTWO\nTHREE\n", "mutation.second_round")
            }

            Step("overlapping ranges reject admission and withdrawal releases reservations") {
                let workspace = try TestWorkspace("mutation-coordination-conflict")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("first\nsecond\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let first = await coordinator.participant(name: "first")
                let second = await coordinator.participant(name: "second")
                let held = try await first.submit(.editText(
                    at: file,
                    operations: [.replaceLineGuarded(1, expected: "first", with: "FIRST")]
                ))
                var rejected = false
                do {
                    _ = try await second.submit(.editText(
                        at: file,
                        operations: [.replaceLineGuarded(1, expected: "first", with: "OTHER")]
                    ))
                } catch StandardMutationCoordinationError.conflict {
                    rejected = true
                }
                try Expect.true(rejected, "mutation.range_conflict")
                try await first.withdraw(held.id)
                _ = try await second.submit(.editText(
                    at: file,
                    operations: [.replaceLineGuarded(1, expected: "first", with: "OTHER")]
                ))
                _ = try Expect.notNil(try await coordinator.publish(), "mutation.conflict_recovered")
                try Expect.equal(try workspace.read(file), "OTHER\nsecond\n", "mutation.withdraw_releases")
            }

            Step("whole-resource reservations exclude edits, and external drift prevents publication") {
                let workspace = try TestWorkspace("mutation-coordination-drift")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("first\nsecond\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let first = await coordinator.participant(name: "first")
                let second = await coordinator.participant(name: "second")
                _ = try await first.submit(.replaceText(at: file, content: "replaced\n"))
                var rejected = false
                do {
                    _ = try await second.submit(.editText(
                        at: file,
                        operations: [.replaceLineGuarded(2, expected: "second", with: "SECOND")]
                    ))
                } catch StandardMutationCoordinationError.conflict {
                    rejected = true
                }
                try Expect.true(rejected, "mutation.resource_conflict")
                _ = try StandardWriter(file).write("external\n", options: .overwriteWithoutBackup)
                var stale = false
                do {
                    _ = try await coordinator.publish()
                } catch StandardMutationError.drift_detected {
                    stale = true
                }
                try Expect.true(stale, "mutation.external_drift")
                try Expect.equal(try workspace.read(file), "external\n", "mutation.external_preserved")
            }

            Step("prepared mutation plan retains approval identity through submission and publication") {
                let workspace = try TestWorkspace("mutation-coordination-external-plan")
                defer { workspace.remove() }
                let file = workspace.file("approved.swift")
                _ = try StandardWriter(file).write("before\nafter\n", options: .overwriteWithoutBackup)

                let approved = try StandardMutationPlanner().plan([
                    .editText(
                        at: file,
                        operations: [.replaceLineGuarded(1, expected: "before", with: "BEFORE")],
                        constraint: .small
                    )
                ], metadata: ["approval": "preview-42", "session": "session-A"])
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "session-A")
                let accepted = try await participant.submit(approved)
                try Expect.equal(accepted.plan, approved, "prepared.source_value_unchanged")
                try Expect.equal(accepted.plan.id, approved.id, "prepared.plan_id")
                try Expect.equal(accepted.plan.metadata["approval"], "preview-42", "prepared.approval")
                let staged = try Expect.notNil(try await coordinator.staged_plan(), "prepared.staged")
                try Expect.equal(staged.id, approved.id, "prepared.staged_id")
                try Expect.equal(try workspace.read(file), "before\nafter\n", "prepared.no_disk_effect")

                let committed = try Expect.notNil(try await coordinator.publish(), "prepared.publication")
                try Expect.equal(committed.result.status, .applied, "prepared.status")
                try Expect.equal(committed.result.plan.id, approved.id, "prepared.published_plan_id")
                try Expect.equal(committed.contributions[0].source_plan_id, approved.id, "prepared.contribution_id")
                try Expect.equal(committed.contributions[0].source_plan_metadata["approval"], "preview-42", "prepared.contribution_metadata")
                try Expect.equal(try workspace.read(file), "BEFORE\nafter\n", "prepared.content")
            }

            Step("prepared plan and convenience submission merge with separate provenance") {
                let workspace = try TestWorkspace("mutation-coordination-prepared-merge")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("one\ntwo\nthree\n", options: .overwriteWithoutBackup)
                let approved = try StandardMutationPlanner().plan([
                    .editText(at: file, operations: [.replaceLineGuarded(1, expected: "one", with: "ONE")])
                ], metadata: ["approval": "first-reviewed"])
                let coordinator = StandardMutationCoordinator()
                let first = await coordinator.participant(name: "first")
                let second = await coordinator.participant(name: "second")
                let a = try await first.submit(approved)
                let b = try await second.submit(
                    .editText(at: file, operations: [.replaceLineGuarded(3, expected: "three", with: "THREE")]),
                    metadata: ["approval": "second-reviewed"]
                )
                try Expect.equal(a.plan.id, approved.id, "prepared.merged_source_id")
                let publication = try Expect.notNil(try await coordinator.publish(), "prepared.merged")
                try Expect.equal(publication.result.status, .applied, "prepared.merged_status")
                try Expect.equal(publication.result.records.count, 1, "prepared.one_write")
                let first_record = try Expect.notNil(publication.contributions.first(where: { $0.submission_id == a.id }), "prepared.first_provenance")
                let second_record = try Expect.notNil(publication.contributions.first(where: { $0.submission_id == b.id }), "prepared.second_provenance")
                try Expect.equal(first_record.source_plan_id, approved.id, "prepared.first_plan")
                try Expect.equal(first_record.source_plan_metadata["approval"], "first-reviewed", "prepared.first_approval")
                try Expect.equal(second_record.source_plan_metadata["approval"], "second-reviewed", "prepared.second_approval")
                try Expect.equal(first_record.entries[0].mutation_record_id, second_record.entries[0].mutation_record_id, "prepared.shared_record")
                try Expect.equal(try workspace.read(file), "ONE\ntwo\nTHREE\n", "prepared.merged_content")
            }

            Step("closed participant rejects raw entries before planning") {
                let workspace = try TestWorkspace("mutation-coordination-closed-before-plan")
                defer { workspace.remove() }
                let missing = workspace.file("missing.swift")
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "closed")
                try await participant.close()
                var rejected_as_closed = false
                do {
                    _ = try await participant.submit(.editText(
                        at: missing, operations: [.replaceLine(1, with: "nope")]
                    ))
                } catch StandardMutationCoordinationError.closed_participant {
                    rejected_as_closed = true
                }
                try Expect.true(rejected_as_closed, "prepared.closed_before_disk_read")
            }

            Step("single submission publishes the approved plan without replanning") {
                let workspace = try TestWorkspace("mutation-coordination-approved-plan")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("alpha\nbeta\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "approval")
                let submitted = try await participant.submit(.editText(
                    at: file,
                    operations: [.replaceLineGuarded(1, expected: "alpha", with: "ALPHA")],
                    constraint: .small
                ))
                let publication = try Expect.notNil(try await coordinator.publish(), "mutation.approved_plan")
                try Expect.equal(publication.result.plan.id, submitted.plan.id, "mutation.plan_identity")
                try Expect.equal(publication.result.plan.entries[0].entry, submitted.plan.entries[0].entry, "mutation.approved_entry")
                try Expect.equal(try workspace.read(file), "ALPHA\nbeta\n", "mutation.approved_effect")
            }

            Step("same submission cannot overlap a directory resource and a descendant edit") {
                let workspace = try TestWorkspace("mutation-coordination-internal-collision")
                defer { workspace.remove() }
                let folder = workspace.file("tree")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let child = folder.appendingPathComponent("nested.txt")
                _ = try StandardWriter(child).write("old\n", options: .overwriteWithoutBackup)
                let destination = workspace.file("tree-copy")
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "collision")
                var refused = false
                do {
                    _ = try await participant.submit([
                        .copy(from: folder, to: destination),
                        .editText(at: child, operations: [.replaceLineGuarded(1, expected: "old", with: "new")])
                    ])
                } catch StandardMutationCoordinationError.overlapping_submission_footprints {
                    refused = true
                }
                try Expect.true(refused, "mutation.internal_footprint_conflict")
                try Expect.equal(try workspace.read(child), "old\n", "mutation.unchanged_after_reject")
            }

            Step("incompatible same-file publication options fail during admission") {
                let workspace = try TestWorkspace("mutation-coordination-options")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("alpha\nbeta\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let first = await coordinator.participant(name: "first")
                let second = await coordinator.participant(name: "second")
                let held = try await first.submit(.editText(
                    at: file,
                    operations: [.replaceLineGuarded(1, expected: "alpha", with: "ALPHA")],
                    options: .init(write: .overwriteWithoutBackup)
                ))
                var refused = false
                do {
                    _ = try await second.submit(.editText(
                        at: file,
                        operations: [.replaceLineGuarded(2, expected: "beta", with: "BETA")]
                    ))
                } catch StandardMutationCoordinationError.incompatible_edit_options {
                    refused = true
                }
                try Expect.true(refused, "mutation.options_conflict_at_submit")
                try await first.withdraw(held.id)
                _ = try await second.submit(.editText(
                    at: file,
                    operations: [.replaceLineGuarded(2, expected: "beta", with: "BETA")]
                ))
                _ = try Expect.notNil(try await coordinator.publish(), "mutation.publish_after_withdraw")
                try Expect.equal(try workspace.read(file), "alpha\nBETA\n", "mutation.options_recovered")
            }

            Step("merged edits retain source plan identity and record attribution") {
                let workspace = try TestWorkspace("mutation-coordination-attribution-merged")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("one\ntwo\nthree\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let first = await coordinator.participant(name: "agent-A")
                let second = await coordinator.participant(name: "agent-B")
                let a = try await first.submit(
                    .editText(at: file, operations: [.replaceLineGuarded(1, expected: "one", with: "ONE")], constraint: .small),
                    metadata: ["agent": "A", "approval": "A-1"]
                )
                let b = try await second.submit(
                    .editText(at: file, operations: [.replaceLineGuarded(3, expected: "three", with: "THREE")], constraint: .small),
                    metadata: ["agent": "B", "approval": "B-1"]
                )
                let publication = try Expect.notNil(try await coordinator.publish(), "mutation.merged_publication")
                try Expect.equal(publication.result.status, .applied, "mutation.merged_status")
                try Expect.equal(publication.result.records.count, 1, "mutation.single_physical_write")
                try Expect.equal(publication.contributions.count, 2, "mutation.two_contributors")
                let contributed_a = try Expect.notNil(
                    publication.contributions.first(where: { $0.submission_id == a.id }), "mutation.contribution_a"
                )
                let contributed_b = try Expect.notNil(
                    publication.contributions.first(where: { $0.submission_id == b.id }), "mutation.contribution_b"
                )
                try Expect.equal(contributed_a.participant_id, first.id, "mutation.agent_a")
                try Expect.equal(contributed_b.participant_id, second.id, "mutation.agent_b")
                try Expect.equal(contributed_a.source_plan_id, a.plan.id, "mutation.plan_a")
                try Expect.equal(contributed_b.source_plan_id, b.plan.id, "mutation.plan_b")
                try Expect.equal(contributed_a.source_plan_metadata["approval"], "A-1", "mutation.approval_a")
                try Expect.equal(contributed_b.source_plan_metadata["approval"], "B-1", "mutation.approval_b")
                try Expect.equal(contributed_a.entries[0].source_entry_id, a.plan.entries[0].id, "mutation.source_a")
                try Expect.equal(contributed_b.entries[0].source_entry_id, b.plan.entries[0].id, "mutation.source_b")
                try Expect.equal(contributed_a.entries[0].published_entry_id, contributed_b.entries[0].published_entry_id, "mutation.shared_entry")
                try Expect.equal(contributed_a.entries[0].mutation_record_id, publication.result.records[0].id, "mutation.record_a")
                try Expect.equal(contributed_b.entries[0].mutation_record_id, publication.result.records[0].id, "mutation.record_b")
                try Expect.true(contributed_a.entries[0].was_applied, "mutation.applied_a")
                try Expect.true(contributed_b.entries[0].was_applied, "mutation.applied_b")
                let roundtrip = try JSONDecoder().decode(StandardMutationPublication.self, from: JSONEncoder().encode(publication))
                try Expect.equal(roundtrip.contributions, publication.contributions, "mutation.attribution_roundtrip")
                try Expect.equal(try workspace.read(file), "ONE\ntwo\nTHREE\n", "mutation.content")
            }

            Step("separate resources retain independent attribution, withdrawn edits excluded") {
                let workspace = try TestWorkspace("mutation-coordination-attribution-resources")
                defer { workspace.remove() }
                let file_a = workspace.file("a.txt")
                let file_b = workspace.file("b.txt")
                let file_c = workspace.file("c.txt")
                let coordinator = StandardMutationCoordinator()
                let a = await coordinator.participant(name: "A")
                let b = await coordinator.participant(name: "B")
                let withdrawn = try await a.submit(.createText(at: file_c, content: "withdrawn\n"))
                try await a.withdraw(withdrawn.id)
                let submitted_a = try await a.submit(.createText(at: file_a, content: "A\n"))
                let submitted_b = try await b.submit(.createText(at: file_b, content: "B\n"))
                let publication = try Expect.notNil(try await coordinator.publish(), "mutation.resource_publication")
                try Expect.equal(publication.result.status, .applied, "mutation.resource_status")
                try Expect.equal(publication.contributions.count, 2, "mutation.only_pending")
                try Expect.equal(publication.submission_ids, [submitted_a.id, submitted_b.id], "mutation.submission_order")
                try Expect.true(publication.contributions.allSatisfy { $0.entries[0].was_applied }, "mutation.all_applied")
                try Expect.true(publication.contributions[0].entries[0].published_entry_id != publication.contributions[1].entries[0].published_entry_id, "mutation.separate_physical_entries")
                try Expect.equal(try workspace.read(file_a), "A\n", "mutation.file_a")
                try Expect.equal(try workspace.read(file_b), "B\n", "mutation.file_b")
                try Expect.false(FileManager.default.fileExists(atPath: file_c.path), "mutation.withdrawn_absent")
            }

            Step("owner rollback restores an entire merged publication and journals it") {
                let workspace = try TestWorkspace("mutation-coordination-rollback-merged")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("one\ntwo\nthree\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let a = await coordinator.participant(name: "a")
                let b = await coordinator.participant(name: "b")
                let first = try await a.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(1, expected: "one", with: "ONE")]
                ))
                let second = try await b.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(3, expected: "three", with: "THREE")]
                ))
                let publication = try Expect.notNil(try await coordinator.publish(), "rollback.publication")
                try Expect.equal(try workspace.read(file), "ONE\ntwo\nTHREE\n", "rollback.published")
                let undone = try await coordinator.rollback(publication_id: publication.result.id)
                try Expect.equal(undone.status, .applied, "rollback.result")
                try Expect.equal(try workspace.read(file), "one\ntwo\nthree\n", "rollback.restored")
                try Expect.equal(await coordinator.rollback_journal().count, 1, "rollback.journal")
                let journal = await coordinator.journal()
                for id in [first.id, second.id] {
                    let item = try Expect.notNil(journal.first(where: { $0.id == id }), "rollback.submission")
                    guard case .rolled_back = item.state else {
                        throw StandardMutationCoordinationError.submission_not_pending(id)
                    }
                }
                var rejected = false
                do {
                    _ = try await coordinator.rollback(publication_id: publication.result.id)
                } catch StandardMutationCoordinationError.publication_already_rolled_back {
                    rejected = true
                }
                try Expect.true(rejected, "rollback.not_twice")
            }

            Step("rollback respects pending reservations") {
                let workspace = try TestWorkspace("mutation-coordination-rollback-reserved")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("base\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let first = await coordinator.participant(name: "first")
                let second = await coordinator.participant(name: "second")
                _ = try await first.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(1, expected: "base", with: "NEW")]
                ))
                let publication = try Expect.notNil(try await coordinator.publish(), "rollback.publication")
                let held = try await second.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(1, expected: "NEW", with: "LATER")]
                ))
                var contested = false
                do {
                    _ = try await coordinator.rollback(publication_id: publication.result.id)
                } catch StandardMutationCoordinationError.conflict {
                    contested = true
                }
                try Expect.true(contested, "rollback.pending_conflict")
                try Expect.equal(try workspace.read(file), "NEW\n", "rollback.no_effect_on_conflict")
                try await second.withdraw(held.id)
                let result = try await coordinator.rollback(publication_id: publication.result.id)
                try Expect.equal(result.status, .applied, "rollback.after_withdraw")
                try Expect.equal(try workspace.read(file), "base\n", "rollback.after_withdraw_content")
            }

            Step("subsequent published drift blocks stale rollback and requires recovery") {
                let workspace = try TestWorkspace("mutation-coordination-rollback-drift")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("one\ntwo\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "one")
                _ = try await participant.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(1, expected: "one", with: "ONE")]
                ))
                let first = try Expect.notNil(try await coordinator.publish(), "rollback.first")
                _ = try await participant.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(2, expected: "two", with: "TWO")]
                ))
                _ = try Expect.notNil(try await coordinator.publish(), "rollback.second")
                let rollback = try await coordinator.rollback(publication_id: first.result.id)
                try Expect.equal(rollback.status, .failed, "rollback.stale_fails")
                try Expect.true(await coordinator.requires_recovery(), "rollback.fail_closed")
                try Expect.equal(try workspace.read(file), "ONE\nTWO\n", "rollback.later_edits_retained")
                var blocked = false
                do {
                    _ = try await participant.submit(.replaceText(at: file, content: "unsafe\n"))
                } catch StandardMutationCoordinationError.requires_recovery {
                    blocked = true
                }
                try Expect.true(blocked, "rollback.no_submissions_until_reconciled")
            }

            Step("staged inspection composes disjoint changes without publishing") {
                let workspace = try TestWorkspace("mutation-coordination-staged")
                defer { workspace.remove() }
                let file = workspace.file("shared.swift")
                _ = try StandardWriter(file).write("one\ntwo\nthree\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let a = await coordinator.participant(name: "A")
                let b = await coordinator.participant(name: "B")
                _ = try await a.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(1, expected: "one", with: "ONE")]
                ))
                _ = try await b.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(3, expected: "three", with: "THREE")]
                ))
                let view = try Expect.notNil(try await coordinator.staged_state(at: file), "staged.view")
                try Expect.equal(view.textContent, "ONE\ntwo\nTHREE\n", "staged.combined")
                try Expect.equal(try workspace.read(file), "one\ntwo\nthree\n", "staged.not_published")
                try Expect.equal(await coordinator.pending_submission_ids().count, 2, "staged.pending")
                let cancelled = await coordinator.cancel_pending()
                try Expect.equal(cancelled.count, 2, "staged.cancelled")
                try Expect.equal(await coordinator.pending_submission_ids().count, 0, "staged.released")
                let empty = try await coordinator.staged_plan()
                try Expect.true(empty == nil, "staged.no_plan_after_cancel")
                _ = try await a.submit(.editText(
                    at: file, operations: [.replaceLineGuarded(2, expected: "two", with: "TWO")]
                ))
                let publication = try Expect.notNil(try await coordinator.publish(), "staged.after_cancel")
                try Expect.equal(publication.result.status, .applied, "staged.next_round")
                try Expect.equal(try workspace.read(file), "one\nTWO\nthree\n", "staged.next_round_content")
            }

            Step("staged creation and deletion are distinguishable from unaffected") {
                let workspace = try TestWorkspace("mutation-coordination-staged-resources")
                defer { workspace.remove() }
                let file = workspace.file("old.txt")
                let created = workspace.file("new.txt")
                let unaffected = workspace.file("untouched.txt")
                _ = try StandardWriter(file).write("old\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "A")
                _ = try await participant.submit([
                    .delete(.init(target: file)),
                    .createText(at: created, content: "new\n")
                ])
                let deleted_view = try Expect.notNil(try await coordinator.staged_state(at: file), "staged.deleted")
                try Expect.equal(deleted_view, .missing, "staged.missing")
                let new_view = try Expect.notNil(try await coordinator.staged_state(at: created), "staged.new")
                try Expect.equal(new_view.textContent, "new\n", "staged.new_content")
                try Expect.true(try await coordinator.staged_state(at: unaffected) == nil, "staged.unaffected")
                try Expect.equal(try workspace.read(file), "old\n", "staged.original_still_exists")
                try Expect.false(FileManager.default.fileExists(atPath: created.path), "staged.create_not_published")
            }

            Step("copy and move have no misleading staged file view") {
                let workspace = try TestWorkspace("mutation-coordination-staged-copy")
                defer { workspace.remove() }
                let source = workspace.file("from.txt")
                let destination = workspace.file("to.txt")
                _ = try StandardWriter(source).write("copied\n", options: .overwriteWithoutBackup)
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "A")
                _ = try await participant.submit(.copy(.init(source: source, destination: destination)))
                var unsupported = false
                do {
                    _ = try await coordinator.staged_state(at: destination)
                } catch StandardMutationCoordinationError.staged_visibility_unsupported {
                    unsupported = true
                }
                try Expect.true(unsupported, "staged.no_false_copy_projection")
                try Expect.false(FileManager.default.fileExists(atPath: destination.path), "staged.no_copy_effect")
            }

            Step("create, copy, move and delete use the canonical mutation applier") {
                let workspace = try TestWorkspace("mutation-coordination-resources")
                defer { workspace.remove() }
                let a = workspace.file("a.txt")
                let b = workspace.file("b.txt")
                let c = workspace.file("c.txt")
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "resources")
                _ = try await participant.submit(.createText(at: a, content: "hello\n"))
                let created = try Expect.notNil(try await coordinator.publish(), "mutation.create")
                try Expect.equal(created.result.status, .applied, "mutation.create_status")
                _ = try await participant.submit(.copy(.init(source: a, destination: b)))
                let copied = try Expect.notNil(try await coordinator.publish(), "mutation.copy")
                try Expect.equal(copied.result.status, .applied, "mutation.copy_status")
                _ = try await participant.submit(.move(.init(source: b, destination: c)))
                let moved = try Expect.notNil(try await coordinator.publish(), "mutation.move")
                try Expect.equal(moved.result.status, .applied, "mutation.move_status")
                _ = try await participant.submit(.delete(.init(target: a)))
                let deleted = try Expect.notNil(try await coordinator.publish(), "mutation.delete")
                try Expect.equal(deleted.result.status, .applied, "mutation.delete_status")
                try Expect.equal(try workspace.read(c), "hello\n", "mutation.resource_content")
            }
        }
    }
}
