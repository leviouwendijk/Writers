import Foundation
import Difference

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
        let fm = FileManager.default
        var bu = backupURL ?? defaultBackupURL(
            suffix: backupSuffix
        )

        if !fm.fileExists(atPath: bu.path),
           options.createBackupDirectory,
           let setURL = latestSetBackupURL(options: options) {
            bu = setURL
        }

        guard fm.fileExists(atPath: bu.path) else {
            throw SafeFileError.backupNotFound(
                bu
            )
        }

        guard fm.fileExists(atPath: url.path) else {
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
        let fm = FileManager.default

        var bu = backupURL ?? defaultBackupURL(suffix: backupSuffix)
        if !fm.fileExists(atPath: bu.path),
           options.createBackupDirectory,
           let setURL = latestSetBackupURL(options: options) {
            bu = setURL
        }

        guard fm.fileExists(atPath: bu.path) else { throw SafeFileError.backupNotFound(bu) }

        if fm.fileExists(atPath: url.path), keepCurrentAsRestorePoint {
            let rp = timestampedSibling(for: url, extraSuffix: ".restore_point.bak")
            try fm.copyItem(at: url, to: rp)
        }

        let tmp = timestampedSibling(for: url, extraSuffix: ".tmp.restore")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: bu, to: tmp)
        try replaceItem(at: url, with: tmp)
        return url
    }
}

// lower level
public extension SafelyWritable {
    @inlinable
    func ensureParentExists(createIfNeeded: Bool) throws {
        let parent = url.deletingLastPathComponent()
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: parent.path, isDirectory: &isDir) {
            if !isDir.boolValue { throw SafeFileError.parentDirectoryMissing(url) }
            return
        }
        if createIfNeeded {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        } else {
            throw SafeFileError.parentDirectoryMissing(url)
        }
    }

    @inlinable
    func fileIsBlank(whitespaceCounts: Bool) throws -> Bool {
        let data = try Data(contentsOf: url, options: .uncached)
        if data.isEmpty { return true }
        guard whitespaceCounts else { return false }
        if let s = String(data: data, encoding: .utf8) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    @inlinable
    func makeBackup(suffix: String, addTimestampIfExists: Bool) throws -> URL {
        let fm = FileManager.default
        var bu = defaultBackupURL(suffix: suffix)
        if fm.fileExists(atPath: bu.path), addTimestampIfExists {
            bu = timestampedSibling(for: bu)
        }
        try? fm.removeItem(at: bu) // be permissive if not timestamping
        try fm.copyItem(at: url, to: bu)
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
    func replaceItem(at dst: URL, with src: URL) throws {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.moveItem(at: src, to: dst)
        } catch {
            throw SafeFileError.io(underlying: error)
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
    func ensureBackupSetDir(options: SafeWriteOptions, timestamp: String) throws -> URL {
        let fm = FileManager.default
        let base = backupBaseDir(options: options)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let set = base.appendingPathComponent("\(options.backupSetPrefix)\(timestamp)", isDirectory: true)
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        return set
    }

    @inlinable
    func pruneBackupSets(baseDir: URL, prefix: String, keep: Int?) throws {
        guard let keep = keep, keep >= 0 else { return }
        let fm = FileManager.default
        let dirs = try fm.contentsOfDirectory(
                at: baseDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { 
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && $0.lastPathComponent.hasPrefix(prefix) 
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } // timestamp-friendly
        if dirs.count > keep {
            for url in dirs.prefix(dirs.count - keep) { try? fm.removeItem(at: url) }
        }
    }

    @inlinable
    func latestSetBackupURL(options: SafeWriteOptions) -> URL? {
        let fm = FileManager.default
        let base = backupBaseDir(options: options)
        guard let entries = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]),
              !entries.isEmpty else { return nil }
        // pick newest overwrite_<yyyyMMdd_HHmmss>
        let sets = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let newestSet = sets.last else { return nil }
        let candidate = newestSet.appendingPathComponent(url.lastPathComponent, isDirectory: false)
        return fm.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
