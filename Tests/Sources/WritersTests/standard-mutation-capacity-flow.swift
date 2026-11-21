import Foundation
import Testing
import Writers

extension WritersFlowSuite {
    /// Capacity checks against a real FAT32 image (40 MB, files up to 4 GiB − 1).
    /// Sources are sparse files on the host volume, so nothing large is written.
    /// Without `hdiutil` (Linux, sandbox) the flow passes with a note.
    static var capacityFlow: TestFlow {
        TestFlow("mutation-capacity", tags: ["mutations", "capacity", "volumes"]) {
            Step("a pass that cannot fit its volume is refused at planning") {
                #if os(macOS)
                let workspace = try TestWorkspace("mutation-capacity")
                defer { workspace.remove() }
                let image = workspace.file("fat.dmg")
                let mount = workspace.file("fat")
                guard run("/usr/bin/hdiutil", ["create", "-size", "40m", "-fs", "MS-DOS", "-volname", "WCAP", "-quiet", image.path]) == 0,
                      run("/usr/bin/hdiutil", ["attach", image.path, "-mountpoint", mount.path, "-nobrowse", "-quiet"]) == 0
                else {
                    print("  mutation-capacity: hdiutil unavailable; FAT32 checks not exercised")
                    return
                }
                defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"]) }

                let huge = workspace.file("huge.bin")
                try sparse(huge, size: 5 << 30)
                var tooLarge = false
                do {
                    _ = try StandardMutationPlanner().plan([
                        .copy(.init(source: huge, destination: mount.appendingPathComponent("huge.bin")))
                    ])
                } catch StandardMutationError.exceeds_file_size_limit(_, _, let size, let limit) {
                    tooLarge = size == 5 << 30 && limit == (1 << 32) - 1
                }
                try Expect.true(tooLarge, "capacity.fat32_file_limit")

                let large = workspace.file("large.bin")
                try sparse(large, size: 64 << 20)
                var full = false
                do {
                    _ = try StandardMutationPlanner().plan([
                        .copy(.init(source: large, destination: mount.appendingPathComponent("large.bin")))
                    ])
                } catch StandardMutationError.insufficient_space(_, let needed, let available) {
                    full = needed >= 64 << 20 && available < needed
                }
                try Expect.true(full, "capacity.insufficient_space")

                // Two copies that fit alone but not together.
                let first = workspace.file("first.bin")
                let second = workspace.file("second.bin")
                try sparse(first, size: 24 << 20)
                try sparse(second, size: 24 << 20)
                var summed = false
                do {
                    _ = try StandardMutationPlanner().plan([
                        .copy(.init(source: first, destination: mount.appendingPathComponent("a.bin"))),
                        .copy(.init(source: second, destination: mount.appendingPathComponent("b.bin"))),
                    ])
                } catch StandardMutationError.insufficient_space {
                    summed = true
                }
                try Expect.true(summed, "capacity.summed_per_volume")

                // A move on one volume writes nothing: no capacity check.
                let small = mount.appendingPathComponent("small.txt")
                _ = try StandardWriter(small).write("small\n", options: .overwriteWithoutBackup)
                let plan = try StandardMutationPlanner().plan([
                    .move(.init(source: small, destination: mount.appendingPathComponent("moved.txt")))
                ])
                try Expect.equal(plan.entries.count, 1, "capacity.same_volume_move_planned")

                // The volume fills between planning and publishing: the copy
                // fails cleanly, leaves no destination, and does not block.
                let fits = workspace.file("fits.bin")
                try sparse(fits, size: 16 << 20)
                let landed = mount.appendingPathComponent("fits.bin")
                let coordinator = StandardMutationCoordinator()
                let participant = await coordinator.participant(name: "capacity")
                _ = try await participant.submit(.copy(.init(source: fits, destination: landed)))
                // FAT has no sparse files: extending allocates the clusters.
                let filler = mount.appendingPathComponent("filler.bin")
                _ = try StandardWriter(filler).write("", options: .overwriteWithoutBackup)
                _ = truncate(filler.path, off_t(30 << 20))
                let published = try Expect.notNil(try await coordinator.publish(), "capacity.publication")
                try Expect.equal(published.result.status, .failed, "capacity.copy_failed")
                try Expect.equal(published.result.failed?.effect, StandardMutationFailureEffect.none, "capacity.clean_failure")
                try Expect.false(FileManager.default.fileExists(atPath: landed.path), "capacity.no_partial_copy")
                try Expect.false(await coordinator.requires_recovery(), "capacity.not_blocked")
                #endif
            }
        }
    }

    private static func sparse(_ url: URL, size: Int64) throws {
        _ = try StandardWriter(url).write("", options: .overwriteWithoutBackup)
        guard truncate(url.path, off_t(size)) == 0 else {
            throw StandardMutationError.target_missing(url)
        }
    }

    #if os(macOS)
    private static func run(_ executable: String, _ arguments: [String]) -> Int32 {
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
