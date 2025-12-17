import Foundation

public struct SafeFile: Sendable, SafelyWritable {
    public let url: URL

    public init(
        _ url: URL
    ) { 
        self.url = url
    }

    @discardableResult
    public func write(_ data: Data, options: SafeWriteOptions = .init()) throws -> SafeWriteResult {
        do {
            try ensureParentExists(createIfNeeded: options.createIntermediateDirectories)

            let fm = FileManager.default
            var backupURL: URL? = nil
            var overwritten = false

            if fm.fileExists(atPath: url.path) {
                let isBlank = try fileIsBlank(whitespaceCounts: options.whitespaceOnlyIsBlank)
                if !isBlank && !options.overrideExisting { throw SafeFileError.fileExistsAndNotBlank(url) }

                if !isBlank && options.overrideExisting, options.makeBackupOnOverride {
                    overwritten = true
                    if options.createBackupDirectory {
                        let ts = timestampString()
                        let setDir = try ensureBackupSetDir(options: options, timestamp: ts)
                        let dst = setDir.appendingPathComponent(url.lastPathComponent, isDirectory: false)
                        try? fm.removeItem(at: dst)
                        try fm.copyItem(at: url, to: dst)
                        backupURL = dst
                        try pruneBackupSets(
                            baseDir: setDir.deletingLastPathComponent(),
                            prefix: options.backupSetPrefix,
                            keep: options.maxBackupSets
                        )
                    } else {
                        backupURL = try makeBackup(
                            suffix: options.backupSuffix,
                            addTimestampIfExists: options.addTimestampIfBackupExists
                        )
                    }
                }
            }

            let writeOpts: Data.WritingOptions = options.atomic ? [.atomic] : []
            try data.write(to: url, options: writeOpts)

            return .init(
                target: url,
                wrote: true,
                backupURL: backupURL,
                overwrittenExisting: overwritten,
                bytesWritten: data.count
            )
        } catch let e as SafeFileError {
            throw e
        } catch {
            throw SafeFileError.io(underlying: error)
        }
    }

    @discardableResult
    public func write(
        _ string: String,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> SafeWriteResult {
        guard let data = string.data(using: encoding) else {
            throw SafeFileError.io(underlying: NSError(
                domain: "SafeFile",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "String encoding failed"]
            ))
        }
        return try write(data, options: options)
    }
}

// let file = SafeFile(URL(fileURLWithPath: "/path/to/output.txt"))

// // 1) Safe write (will throw if non-blank file exists)
// try file.write("Hello\n")

// // 2) Override with backup
// var opts = SafeWriteOptions(overrideExisting: true, makeBackupOnOverride: true)
// try file.write("Hello new world\n", options: opts)

// // 3) Show diff against backup
// let diff = try file.diffAgainstBackup()
// print(diff)

// // 4) Restore from backup
// try file.restoreFromBackup()
