import Foundation
import IO

/// Whole-file writes through IO.
///
/// Atomic writes stage the bytes in an exclusive sibling temp file, then
/// publish with one native operation:
///
/// - existing target: `FileSystem.replace` (Darwin `RENAME_SWAP`, after giving
///   the replacement the original's mode, birth time and ACL);
/// - new target: a no-replace rename (`RENAME_EXCL`), so a file that appeared
///   since the plan was validated is never overwritten (`EEXIST`).
///
/// Symlinks are written through (the link is kept, its target receives the
/// bytes). The resolve that requires costs syscalls only when a symlink is
/// actually met: replace checks after its regular-file fast path declines,
/// create checks after the rename reports `EEXIST`.
///
/// `durable` adds `F_FULLFSYNC` before publish. Without it the publish is still
/// atomic for every observer, but not guaranteed across power loss.
///
/// Success-path syscalls: open(temp) + write… + close + publish
/// (+ F_FULLFSYNC when durable).
enum FileWriteCommit {
    /// `replacingExisting` comes from the validated plan, not from a fresh
    /// probe: a plan that expected to create never replaces a file that
    /// appeared since, and a plan that expected to replace fails if the file
    /// is gone.
    static func write(
        _ data: Data,
        to url: URL,
        replacingExisting: Bool,
        atomic: Bool,
        durable: Bool
    ) throws {
        let fileSystem = FileSystem.default

        guard atomic else {
            // The open follows symlinks itself.
            try writeFile(
                data,
                to: url,
                mode: .truncate,
                permissions: 0o666,
                durable: durable
            )
            return
        }

        let staging = stagingURL(
            for: url
        )

        do {
            // A replacement receives the original's mode before it becomes
            // visible at the target; until then keep it private. A new file
            // gets the ordinary umask-derived mode.
            try writeFile(
                data,
                to: staging,
                mode: .create,
                permissions: replacingExisting ? 0o600 : 0o666,
                durable: durable
            )

            if replacingExisting {
                try fileSystem.replace(
                    url,
                    with: staging,
                    followingSymlinks: true
                )
            } else {
                try create(
                    staging,
                    at: url
                )
            }
        } catch {
            try? fileSystem.remove(
                staging
            )
            throw error
        }
    }

    /// Unique hidden sibling: same directory (same filesystem for rename/swap),
    /// never reused, created with `O_EXCL`.
    static func stagingURL(
        for target: URL
    ) -> URL {
        target
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(target.lastPathComponent).\(UUID().uuidString).tmp",
                isDirectory: false
            )
    }

    /// No-replace publish. `EEXIST` is final unless the occupant is a dangling
    /// symlink, whose missing target is the file to create; that check runs
    /// only on the error path.
    private static func create(
        _ staging: URL,
        at url: URL
    ) throws {
        let fileSystem = FileSystem.default

        do {
            try fileSystem.move(
                staging,
                to: url
            )
        } catch let error as FileSystemError
            where error.errno == EEXIST
        {
            let link = try FileInspector(
                url
            ).inspect()

            guard link.kind == .symlink,
                  try !FileInspector(
                    url
                  ).inspect(
                    followingSymlinks: true
                  ).existed
            else {
                throw error
            }

            try fileSystem.move(
                staging,
                to: fileSystem.resolve(
                    url
                )
            )
        }
    }

    private static func writeFile(
        _ data: Data,
        to url: URL,
        mode: SystemFileDestinationMode,
        permissions: UInt16,
        durable: Bool
    ) throws {
        var destination = Destination(
            try SystemFileDestination(
                path: url.path,
                mode: mode,
                permissions: permissions
            )
        )

        let written = try data.withUnsafeBytes {
            try destination.write(
                $0
            )
        }

        // A regular-file backend never applies backpressure; anything short
        // of complete is an endpoint fault, not a retry condition.
        guard written == .complete else {
            throw FileWriteCommitError.incomplete_write(
                url
            )
        }

        if durable {
            guard try destination.synchronize() == .complete else {
                throw FileWriteCommitError.incomplete_write(
                    url
                )
            }
        }

        try destination.close()
    }
}

public enum FileWriteCommitError: Error, Sendable, LocalizedError, Hashable {
    case incomplete_write(URL)

    public var errorDescription: String? {
        switch self {
        case .incomplete_write(let url):
            return "Write to \(url.path) did not complete."
        }
    }
}
