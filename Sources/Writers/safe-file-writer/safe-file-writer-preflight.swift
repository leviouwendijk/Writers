import Foundation

public func preflightSafeWrite(
    _ targets: [URL],
    options: SafeWriteOptions
) throws {
    let fm = FileManager.default

    func isNonBlank(_ url: URL) -> Bool {
        guard fm.fileExists(atPath: url.path) else { return false }
        guard let data = try? Data(contentsOf: url, options: .uncached) else { return false }
        if data.isEmpty { return false }
        if options.whitespaceOnlyIsBlank,
           let s = String(data: data, encoding: .utf8),
           s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    let collisions = targets.filter(isNonBlank)
    if !collisions.isEmpty && options.overrideExisting == false {
        throw SafePreflightError.refusingToOverwrite(collisions)
    }

    guard options.overrideExisting && options.makeBackupOnOverride else { return }

    // Single timestamp per preflight run for nicer grouping
    // (we’ll still create one set per *directory*)
    let ts: String = SafeFile(URL(fileURLWithPath: "/dev/null")).timestampString()

    for url in collisions {
        if options.createBackupDirectory {
            let sf = SafeFile(url)
            let setDir = try sf.ensureBackupSetDir(options: options, timestamp: ts)
            let dst = setDir.appendingPathComponent(url.lastPathComponent, isDirectory: false)
            if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
            try fm.copyItem(at: url, to: dst)
            try sf.pruneBackupSets(
                baseDir: setDir.deletingLastPathComponent(),
                prefix: options.backupSetPrefix,
                keep: options.maxBackupSets
            )
        } else {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + options.backupSuffix, isDirectory: false)
            if fm.fileExists(atPath: backup.path) {
                let tsBackup = url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + ".\(ts)" + options.backupSuffix, isDirectory: false)
                try fm.copyItem(at: url, to: tsBackup)
            } else {
                try fm.copyItem(at: url, to: backup)
            }
        }
    }
}
