import Foundation
import Difference
import IO
import Readers

public extension SafelyWritable {
    @inlinable
    func defaultBackupURL(suffix: String) -> URL {
        url.deletingLastPathComponent()
        .appendingPathComponent(url.lastPathComponent + suffix, isDirectory: false)
    }

    @inlinable
    func diffAgainstBackup(
        backupURL: URL? = nil,
        encoding: String.Encoding = .utf8,
        backupSuffix: String = "_previous_version.bak",
        options: SafeWriteOptions = .init(),
        renderOptions: DifferenceRenderOptions = .unified
    ) throws -> String {
        let difference = try structuredDiffAgainstBackup(
            backupURL: backupURL,
            encoding: encoding,
            backupSuffix: backupSuffix,
            options: options
        )

        return DifferenceRenderer.render(
            difference,
            options: renderOptions
        )
    }

    @inlinable
    func structuredDiffAgainstBackup(
        backupURL: URL? = nil,
        encoding: String.Encoding = .utf8,
        backupSuffix: String = "_previous_version.bak",
        options: SafeWriteOptions = .init()
    ) throws -> TextDifference {
        let fileSystem = FileSystem.default
        var bu = backupURL ?? defaultBackupURL(
            suffix: backupSuffix
        )

        if !fileSystem.exists(
            bu
        ),
           options.createBackupDirectory,
           let setURL = latestSetBackupURL(options: options) {
            bu = setURL
        }

        guard fileSystem.exists(
            bu
        ) else {
            throw SafeFileError.backupNotFound(
                bu
            )
        }

        guard fileSystem.exists(
            url
        ) else {
            throw SafeFileError.nothingToRestore(
                url
            )
        }

        let oldStr = try IntegratedReader.text(
            at: bu,
            encoding: encoding,
            missingFileReturnsEmpty: false,
            normalizeNewlines: false
        )

        let newStr = try IntegratedReader.text(
            at: url,
            encoding: encoding,
            missingFileReturnsEmpty: false,
            normalizeNewlines: false
        )

        return WriteDifference.lines(
            old: oldStr,
            new: newStr,
            oldName: bu.lastPathComponent,
            newName: url.lastPathComponent
        )
    }

    /// Restores the backup over the current file. By default, preserves the current file
    /// to a timestamped ".restore_point.bak".
    @discardableResult
    func restoreFromBackup(
        backupURL: URL? = nil,
        backupSuffix: String = "_previous_version.bak",
        keepCurrentAsRestorePoint: Bool = true,
        options: SafeWriteOptions = .init()
    ) throws -> URL {
        let fileSystem = FileSystem.default

        var bu = backupURL ?? defaultBackupURL(
            suffix: backupSuffix
        )

        if !fileSystem.exists(
            bu
        ),
           options.createBackupDirectory,
           let setURL = latestSetBackupURL(options: options) {
            bu = setURL
        }

        guard fileSystem.exists(
            bu
        ) else {
            throw SafeFileError.backupNotFound(
                bu
            )
        }

        if fileSystem.exists(
            url
        ),
           keepCurrentAsRestorePoint {
            // Exclusive and unique: a same-second restore point never
            // replaces an earlier one.
            _ = try LocalWriteBackup.timestamped(
                of: url,
                suffix: ".restore_point.bak",
                timestamp: timestampString()
            )
        }

        // Unique per restore; never pre-deleted, so concurrent restores cannot
        // clobber each other's staging copy.
        let tmp = url
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(url.lastPathComponent).\(UUID().uuidString).tmp.restore",
                isDirectory: false
            )

        try fileSystem.copy(
            bu,
            to: tmp
        )

        try replaceItem(
            at: url,
            with: tmp
        )

        return url
    }
}

// lower level
public extension SafelyWritable {
    @inlinable
    func ensureParentExists(createIfNeeded: Bool) throws {
        let parent = url.deletingLastPathComponent()
        let inspector = FileInspector(
            parent
        )
        // Follow a symlinked parent (e.g. /tmp on macOS): the write lands in
        // the directory it points to.
        let metadata = try inspector.inspect(
            followingSymlinks: true
        )

        if metadata.existed {
            guard metadata.kind == .directory else {
                throw SafeFileError.parentDirectoryMissing(
                    url
                )
            }

            return
        }

        // Missing when followed but present unfollowed: a dangling symlink.
        // Never create a directory through it.
        if try inspector.inspect().existed {
            throw SafeFileError.parentDirectoryMissing(
                url
            )
        }

        if createIfNeeded {
            try FileSystem.default.directory.create(
                parent
            )
        } else {
            throw SafeFileError.parentDirectoryMissing(
                url
            )
        }
    }

    @inlinable
    func fileIsBlank(whitespaceCounts: Bool) throws -> Bool {
        let data = try DataFileReader(
            url
        ).read(
            options: .init(
                cachePolicy: .uncached
            )
        ).data

        if data.isEmpty {
            return true
        }

        guard whitespaceCounts else {
            return false
        }

        if let string = String(
            data: data,
            encoding: .utf8
        ) {
            return string
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        }

        return false
    }

    /// Publishes `src` at `dst` and consumes `src` (removed on failure).
    @inlinable
    func replaceItem(
        at dst: URL,
        with src: URL
    ) throws {
        let fileSystem = FileSystem.default

        // Never remove-then-move: `dst` must exist at every instant. An
        // existing destination is swapped atomically (keeping its metadata);
        // a missing one gets a no-replace rename. A symlinked destination is
        // written through to its target; replace resolves only when it meets
        // one.
        do {
            if fileSystem.exists(
                dst
            ) {
                try fileSystem.replace(
                    dst,
                    with: src,
                    followingSymlinks: true
                )
            } else {
                try fileSystem.move(
                    src,
                    to: dst
                )
            }
        } catch {
            try? fileSystem.remove(
                src
            )
            throw SafeFileError.io(
                underlying: error
            )
        }
    }

    @inlinable
    func timestampString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: Date())
    }

    @inlinable
    func backupBaseDir(options: SafeWriteOptions) -> URL {
        url.deletingLastPathComponent()
           .appendingPathComponent(options.backupDirectoryName, isDirectory: true)
    }

    @inlinable
    func ensureBackupSetDir(
        options: SafeWriteOptions,
        timestamp: String
    ) throws -> URL {
        let fileSystem = FileSystem.default
        let base = backupBaseDir(
            options: options
        )

        try fileSystem.directory.create(
            base
        )

        let set = base.appendingPathComponent(
            "\(options.backupSetPrefix)\(timestamp)",
            isDirectory: true
        )

        try fileSystem.directory.create(
            set
        )

        return set
    }

    /// Keeps the newest `keep` backup sets. `preserving` (the set just written)
    /// is never removed and counts toward `keep`, so `keep: 0` cannot delete
    /// the backup an overwrite is about to rely on.
    @inlinable
    func pruneBackupSets(
        baseDir: URL,
        prefix: String,
        keep: Int?,
        preserving: URL? = nil
    ) throws {
        guard let keep = keep, keep >= 0 else {
            return
        }

        let preservedName = preserving?.standardizedFileURL.lastPathComponent
        let others = preservedName == nil
            ? keep
            : max(0, keep - 1)
        let fileSystem = FileSystem.default

        let dirs = try fileSystem.directory.contents(
            baseDir,
            options: [.skipsHiddenFiles]
        )
        .compactMap { url -> URL? in
            guard
                let metadata = try? FileInspector(
                    url
                ).inspect(),
                metadata.kind == .directory,
                url.lastPathComponent.hasPrefix(
                    prefix
                ),
                url.lastPathComponent != preservedName
            else {
                return nil
            }

            return url
        }
        .sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        if dirs.count > others {
            for url in dirs.prefix(
                dirs.count - others
            ) {
                try? fileSystem.remove(
                    url
                )
            }
        }
    }

    @inlinable
    func latestSetBackupURL(
        options: SafeWriteOptions
    ) -> URL? {
        let fileSystem = FileSystem.default
        let base = backupBaseDir(
            options: options
        )

        guard
            let entries = try? fileSystem.directory.contents(
                base
            ),
            !entries.isEmpty
        else {
            return nil
        }

        let sets = entries
            .compactMap { entry -> URL? in
                guard
                    let metadata = try? FileInspector(
                        entry
                    ).inspect(),
                    metadata.kind == .directory
                else {
                    return nil
                }

                return entry
            }
            .sorted {
                $0.lastPathComponent < $1.lastPathComponent
            }

        // Sets are shared by every file in a directory; the newest set holding
        // this file's backup is the latest one, even if newer sets exist.
        for set in sets.reversed() {
            let candidate = set.appendingPathComponent(
                url.lastPathComponent,
                isDirectory: false
            )

            if fileSystem.exists(
                candidate
            ) {
                return candidate
            }
        }

        return nil
    }
}
