import Difference
import Foundation
import Path
import Testing
import Writers

extension WritersFlowSuite {
    static var semanticMutationDifferenceFlow: TestFlow {
        TestFlow("semantic-mutation-difference", tags: ["difference", "mutation", "planned"]) {
            Step("prepared file edits retain tree and text relations") {
                let workspace = try TestWorkspace("semantic-mutation-difference")
                defer { workspace.remove() }
                let modified = workspace.file("Sources/modified.txt")
                try FileManager.default.createDirectory(
                    at: modified.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try "before\n".write(to: modified, atomically: true, encoding: .utf8)
                let added = workspace.file("Tests/added.txt")
                let plan = try StandardMutationAPI().plan([
                    .replace_text(.init(target: modified, content: "after\n")),
                    .create_text(.init(target: added, content: "new\n")),
                ])
                let semantic = try plan.difference(root: workspace.root)
                try Expect.equal(semantic.structure.source, .planned, "planned provenance")
                try Expect.equal(semantic.contents.count, 2, "text operation count")
                try Expect.equal(semantic.contents.map(\.id), plan.entries.map { $0.id.uuidString }, "operation identities")
                let lines = semantic.layout.tree.lines
                try Expect.true(lines.contains { $0.label == "modified.txt" && $0.change == .modified }, "content-only modification")
                try Expect.true(lines.contains { $0.label == "added.txt" && $0.change == .added }, "created file addition")
                try Expect.true(lines.contains { $0.label == "Tests/" && $0.change == .unchanged }, "parent directory is only grouping scaffolding")
                try Expect.equal(semantic.text_sections().count, 2, "text sections remain separate")
                try Expect.true(semantic.layout.text.hasChanges, "rendered text changes")
                try Expect.false(FileManager.default.fileExists(atPath: added.path), "projection did not apply plan")
            }
            Step("copy and move retain typed structural relationships") {
                let workspace = try TestWorkspace("semantic-mutation-transfers")
                defer { workspace.remove() }
                let original = workspace.file("source.txt")
                try "source\n".write(to: original, atomically: true, encoding: .utf8)
                let moved = workspace.file("renamed.txt")
                let move_plan = try StandardMutationAPI().plan(
                    .move(.init(source: original, destination: moved))
                )
                let relocation = try move_plan.difference(root: workspace.root)
                let entry = relocation.structure.tree.walk().first {
                    $0.node.value.change == .moved
                }?.node.value
                _ = try Expect.notNil(entry, "move detected from declared source/destination")
                try Expect.true(entry?.before?.path != entry?.after?.path, "both move addresses retained")
                try Expect.equal(relocation.structure.source, .planned, "planned move provenance")
                let layout = relocation.make_tree_layout(presenting: { entry in
                    guard entry.change == .moved,
                          let before = entry.before,
                          let after = entry.after else {
                        return .init(label: entry.label)
                    }
                    return .init(
                        label: entry.label,
                        relocation: .init(
                            from: before.path.render(as: .relative, filetype: true),
                            to: after.path.render(as: .relative, filetype: true)
                        )
                    )
                })
                let moveLine = try Expect.notNil(
                    layout.lines.first { $0.change == .moved },
                    "planned move appears in shared layout"
                )
                try Expect.equal(
                    moveLine.relocation?.from,
                    entry?.before?.path.render(as: .relative, filetype: true),
                    "origin retained as a separate value"
                )
                try Expect.equal(
                    moveLine.relocation?.to,
                    entry?.after?.path.render(as: .relative, filetype: true),
                    "destination retained as a separate value"
                )
                let movePlan = TreeDifferenceRenderPlan.make(layout)
                let moveSegments = movePlan.lines.first { $0.change == .moved }?.segments
                try Expect.true(
                    moveSegments?.contains { $0.component == .relocation_from } == true,
                    "render plan retains the origin component"
                )
                try Expect.true(
                    moveSegments?.contains { $0.component == .relocation_to } == true,
                    "render plan retains the destination component"
                )
                try Expect.true(
                    TreeDifferenceRenderer.render(movePlan).contains(" -> "),
                    "renderer presents relocation endpoints"
                )
                try Expect.equal(
                    try JSONDecoder().decode(
                        TreeDifferenceLayout.self,
                        from: JSONEncoder().encode(layout)
                    ),
                    layout,
                    "typed relocation survives serialization"
                )

                let copied = workspace.file("copied.txt")
                let copy_plan = try StandardMutationAPI().plan(
                    .copy(.init(source: original, destination: copied))
                )
                let copying = try copy_plan.difference(root: workspace.root)
                try Expect.true(copying.layout.tree.lines.contains {
                    $0.label == "copied.txt" && $0.change == .added
                }, "copy creates destination")
                try Expect.true(copying.layout.tree.lines.contains {
                    $0.label == "source.txt" && $0.change == .unchanged
                }, "copy preserves source")
            }
        }
    }
}
