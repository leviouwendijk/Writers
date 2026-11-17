import Foundation
import IO

/// Local backup storage shared by `FileWriter` and batch preflight.
///
/// Backups are exclusive clones of the target (`clonefile`: one syscall,
/// copy-on-write, original metadata kept). A clone never replaces, so an
/// earlier backup is never overwritten; a taken name moves on to the next.
/// Callers run after `validateCurrentState`, so the clone matches the plan's
/// fingerprint except within the validate→clone window.
enum LocalWriteBackup {
    /// `<name><suffix>` when free; otherwise, with `addTimestampIfExists`,
    /// `<name>.<timestamp>[-n]<suffix>`. Without it, the base backup is replaced
    /// atomically.
    static func sibling(
        of target: URL,
        suffix: String,
        addTimestampIfExists: Bool,
        timestamp: String
    ) throws -> URL {
        let base = target
            .deletingLastPathComponent()
            .appendingPathComponent(
                target.lastPathComponent + suffix,
                isDirectory: false
            )

        if try cloneIfAbsent(
            target,
            to: base
        ) {
            return base
        }

        guard addTimestampIfExists else {
            let staging = FileWriteCommit.stagingURL(
                for: base
            )

            do {
                try FileSystem.default.copy(
                    target,
                    to: staging
                )
                try FileSystem.default.replace(
                    base,
                    with: staging
                )
            } catch {
                try? FileSystem.default.remove(
                    staging
                )
                throw error
            }

            return base
        }

        return try timestamped(
            of: target,
            suffix: suffix,
            timestamp: timestamp
        )
    }

    /// `<name>.<timestamp>[-n]<suffix>`, the first name not yet taken.
    static func timestamped(
        of target: URL,
        suffix: String,
        timestamp: String
    ) throws -> URL {
        let directory = target.deletingLastPathComponent()
        let name = target.lastPathComponent

        for attempt in 1... {
            let stamp = attempt == 1
                ? timestamp
                : "\(timestamp)-\(attempt)"
            let candidate = directory.appendingPathComponent(
                "\(name).\(stamp)\(suffix)",
                isDirectory: false
            )

            if try cloneIfAbsent(
                target,
                to: candidate
            ) {
                return candidate
            }
        }

        fatalError("unbounded attempt sequence ended")
    }

    /// `<base>/<prefix><timestamp>[-n]/<name>`: the first set for this timestamp
    /// that does not already hold a backup of `target`. Set names sort
    /// chronologically (`…_120000` < `…_120000-2` < `…_120001`).
    static func intoSet(
        of target: URL,
        writer: some SafelyWritable,
        options: SafeWriteOptions,
        timestamp: String
    ) throws -> URL {
        for attempt in 1... {
            let stamp = attempt == 1
                ? timestamp
                : "\(timestamp)-\(attempt)"
            let set = try writer.ensureBackupSetDir(
                options: options,
                timestamp: stamp
            )
            let destination = set.appendingPathComponent(
                target.lastPathComponent,
                isDirectory: false
            )

            if try cloneIfAbsent(
                target,
                to: destination
            ) {
                try writer.pruneBackupSets(
                    baseDir: set.deletingLastPathComponent(),
                    prefix: options.backupSetPrefix,
                    keep: options.maxBackupSets,
                    preserving: set
                )
                return destination
            }
        }

        fatalError("unbounded attempt sequence ended")
    }

    /// Returns false when `destination` already exists; never replaces it.
    private static func cloneIfAbsent(
        _ source: URL,
        to destination: URL
    ) throws -> Bool {
        do {
            try FileSystem.default.copy(
                source,
                to: destination
            )
            return true
        } catch let error as FileSystemError
            where error.errno == EEXIST
        {
            return false
        } catch let error as CocoaError
            where error.code == .fileWriteFileExists
        {
            // Foundation fallback (non-clone volumes, non-Darwin).
            return false
        }
    }
}
