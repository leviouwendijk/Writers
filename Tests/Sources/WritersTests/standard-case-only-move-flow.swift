import Foundation
import Testing
import Writers

extension WritersFlowSuite {
    /// Case-only renames on case-insensitive volumes: the host volume when it is
    /// case-insensitive (default APFS), and an exFAT image (IO's no-replace
    /// fallback). Each part reports and passes when its volume is unavailable.
    static var caseOnlyMoveFlow: TestFlow {
        TestFlow("case-only-move", tags: ["mutations", "move", "volumes"]) {
            Step("case-only move applies and rolls back on the host volume") {
                let workspace = try TestWorkspace("case-only-move-host")
                defer { workspace.remove() }
                try exerciseCaseOnlyMove(in: workspace.root, label: "host")
            }

            Step("case-only move applies and rolls back on exFAT") {
                #if os(macOS)
                let workspace = try TestWorkspace("case-only-move-exfat")
                defer { workspace.remove() }
                let image = workspace.file("case.dmg")
                let mount = workspace.file("exfat")
                guard runTool("/usr/bin/hdiutil", ["create", "-size", "8m", "-fs", "ExFAT", "-volname", "WCASE", "-quiet", image.path]) == 0,
                      runTool("/usr/bin/hdiutil", ["attach", image.path, "-mountpoint", mount.path, "-nobrowse", "-quiet"]) == 0
                else {
                    print("  case-only-move: hdiutil unavailable; exFAT not exercised")
                    return
                }
                defer { _ = runTool("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"]) }
                try exerciseCaseOnlyMove(in: mount, label: "exfat")
                #endif
            }
        }
    }

    private static func exerciseCaseOnlyMove(in root: URL, label: String) throws {
        let probe = root.appendingPathComponent("Probe.txt")
        _ = try StandardWriter(probe).write("probe\n", options: .overwriteWithoutBackup)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("probe.txt").path) else {
            print("  case-only-move: \(label) volume is case-sensitive; not exercised")
            return
        }

        let mixed = root.appendingPathComponent("Photo.JPG")
        let lower = root.appendingPathComponent("photo.jpg")
        _ = try StandardWriter(mixed).write("photo\n", options: .overwriteWithoutBackup)
        let writer = StandardMutationApplier()

        let plan = try StandardMutationPlanner().plan([
            .move(.init(source: mixed, destination: lower))
        ])
        let result = writer.apply(plan)
        try Expect.equal(result.status, .applied, "case.\(label).applied")
        let renamed = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try Expect.true(renamed.contains("photo.jpg"), "case.\(label).new_spelling")
        try Expect.false(renamed.contains("Photo.JPG"), "case.\(label).old_spelling_gone")

        let rollback = try Expect.notNil(result.rollback, "case.\(label).rollback_plan")
        let undone = StandardMutationRollbackApplier().apply(rollback)
        try Expect.equal(undone.status, .applied, "case.\(label).rollback_applied")
        let restored = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try Expect.true(restored.contains("Photo.JPG"), "case.\(label).rollback_spelling")

        // Copying onto another spelling of the same file is a real collision.
        var copyRefused = false
        do {
            _ = try StandardMutationPlanner().plan([
                .copy(.init(source: mixed, destination: lower))
            ])
        } catch StandardMutationError.target_exists {
            copyRefused = true
        }
        try Expect.true(copyRefused, "case.\(label).copy_onto_alias_refused")

        // A different name of an existing file is still a collision.
        let other = root.appendingPathComponent("other.jpg")
        _ = try StandardWriter(other).write("other\n", options: .overwriteWithoutBackup)
        var collision = false
        do {
            _ = try StandardMutationPlanner().plan([
                .move(.init(source: mixed, destination: other))
            ])
        } catch StandardMutationError.target_exists {
            collision = true
        }
        try Expect.true(collision, "case.\(label).different_name_collides")
    }

    #if os(macOS)
    private static func runTool(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
    #endif
}
