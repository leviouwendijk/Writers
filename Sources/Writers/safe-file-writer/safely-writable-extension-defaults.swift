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
    @inlinable
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
            let restorePoint = timestampedSibling(
                for: url,
                extraSuffix: ".restore_point.bak"
            )

            try fileSystem.copy(
                url,
                to: restorePoint
            )
        }

        let tmp = timestampedSibling(
            for: url,
            extraSuffix: ".tmp.restore"
        )

        try? fileSystem.remove(
            tmp
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
        let metadata = try FileInspector(
            parent
        ).inspect()

        if metadata.existed {
            guard metadata.kind == .directory else {
                throw SafeFileError.parentDirectoryMissing(
                    url
                )
            }

            return
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

    @inlinable
    func makeBackup(
        suffix: String,
        addTimestampIfExists: Bool
    ) throws -> URL {
        let fileSystem = FileSystem.default
        var bu = defaultBackupURL(
            suffix: suffix
        )

        if fileSystem.exists(
            bu
        ),
           addTimestampIfExists {
            bu = timestampedSibling(
                for: bu
            )
        }

        try? fileSystem.remove(
            bu
        )

        try fileSystem.copy(
            url,
            to: bu
        )

        return bu
    }

    @inlinable
    func timestampedSibling(for original: URL, extraSuffix: String = "") -> URL {
        // Local timestamp helper; no dependency on conforming type
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let stamp = df.string(from: Date())
        let name = original.lastPathComponent + "." + stamp + extraSuffix
        return original.deletingLastPathComponent().appendingPathComponent(name, isDirectory: false)
    }

    @inlinable
    func replaceItem(
        at dst: URL,
        with src: URL
    ) throws {
        let fileSystem = FileSystem.default

        do {
            if fileSystem.exists(
                dst
            ) {
                try fileSystem.remove(
                    dst
                )
            }

            try fileSystem.move(
                src,
                to: dst
            )
        } catch {
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

    @inlinable
    func pruneBackupSets(
        baseDir: URL,
        prefix: String,
        keep: Int?
    ) throws {
        guard let keep = keep, keep >= 0 else {
            return
        }

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
                )
            else {
                return nil
            }

            return url
        }
        .sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        if dirs.count > keep {
            for url in dirs.prefix(
                dirs.count - keep
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

        guard let newestSet = sets.last else {
            return nil
        }

        let candidate = newestSet.appendingPathComponent(
            url.lastPathComponent,
            isDirectory: false
        )

        return fileSystem.exists(
            candidate
        )
            ? candidate
            : nil
    }
}
