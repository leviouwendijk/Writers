import Foundation

public typealias SafeFile = StandardWriter

public struct StandardWriter: Sendable, SafelyWritable {
    public let url: URL

    public init(
        _ url: URL
    ) {
        self.url = url
    }

    @discardableResult
    public func write(
        _ data: Data,
        options: SafeWriteOptions = .init()
    ) throws -> SafeWriteResult {
        try writePrepared(
            data,
            options: options,
            conflict: overwriteConflict(incomingData: data)
        )
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

        return try writePrepared(
            data,
            options: options,
            conflict: overwriteConflict(
                incomingString: string,
                encoding: encoding
            )
        )
    }

    @discardableResult
    public func write(
        _ string: String,
        content mode: ContentOverwriteMode,
        separator: String? = nil,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> SafeWriteResult {
        switch mode {
        case .replace:
            return try write(
                string,
                encoding: encoding,
                options: options
            )

        case .append:
            let fm = FileManager.default
            var composed = string

            if fm.fileExists(atPath: url.path) {
                let isBlank = try fileIsBlank(
                    whitespaceCounts: options.whitespaceOnlyIsBlank
                )

                if !isBlank {
                    let existing = try IntegratedReader.text(
                        at: url,
                        encoding: encoding,
                        missingFileReturnsEmpty: true,
                        normalizeNewlines: false
                    )

                    if let separator, !separator.isEmpty {
                        composed = existing + separator + string
                    } else {
                        composed = existing + string
                    }
                }
            }

            var writeOptions = options
            writeOptions.existingFilePolicy = .overwrite

            return try write(
                composed,
                encoding: encoding,
                options: writeOptions
            )
        }
    }

    @discardableResult
    private func writePrepared(
        _ data: Data,
        options: SafeWriteOptions,
        conflict: @autoclosure () -> SafeFileOverwriteConflict
    ) throws -> SafeWriteResult {
        do {
            try ensureParentExists(
                createIfNeeded: options.createIntermediateDirectories
            )

            let fm = FileManager.default
            var backupURL: URL? = nil
            var overwritten = false

            if fm.fileExists(atPath: url.path) {
                let isBlank = try fileIsBlank(
                    whitespaceCounts: options.whitespaceOnlyIsBlank
                )

                if !isBlank {
                    switch options.existingFilePolicy {
                    case .abort:
                        throw SafeFileError.overwriteConflict(conflict())

                    case .overwrite:
                        overwritten = true

                        if options.makeBackupOnOverride {
                            if options.createBackupDirectory {
                                let ts = timestampString()
                                let setDir = try ensureBackupSetDir(
                                    options: options,
                                    timestamp: ts
                                )
                                let dst = setDir.appendingPathComponent(
                                    url.lastPathComponent,
                                    isDirectory: false
                                )
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
        } catch let error as SafeFileError {
            throw error
        } catch {
            throw SafeFileError.io(underlying: error)
        }
    }

    private func overwriteConflict(
        incomingData: Data
    ) -> SafeFileOverwriteConflict {
        let existingData = try? IntegratedReader.data(
            at: url,
            missingFileReturnsEmpty: true
        )

        let difference: SafeFileDifference?

        if let existingData,
           let oldString = String(
               data: existingData,
               encoding: .utf8
           ),
           let newString = String(
               data: incomingData,
               encoding: .utf8
           ) {
            difference = makeStructuredLineDiff(
                old: oldString,
                new: newString,
                oldName: "\(url.lastPathComponent) (existing)",
                newName: "\(url.lastPathComponent) (incoming)"
            )
        } else {
            difference = nil
        }

        return .init(
            url: url,
            difference: difference
        )
    }

    private func overwriteConflict(
        incomingString: String,
        encoding: String.Encoding
    ) -> SafeFileOverwriteConflict {
        let oldString = try? IntegratedReader.text(
            at: url,
            encoding: encoding,
            missingFileReturnsEmpty: true,
            normalizeNewlines: false
        )

        let difference = oldString.map {
            makeStructuredLineDiff(
                old: $0,
                new: incomingString,
                oldName: "\(url.lastPathComponent) (existing)",
                newName: "\(url.lastPathComponent) (incoming)"
            )
        }

        return .init(
            url: url,
            difference: difference
        )
    }

    // private func overwriteConflict(
    //     incomingData: Data
    // ) -> SafeFileOverwriteConflict {
    //     let existingData = try? Data(
    //         contentsOf: url,
    //         options: .uncached
    //     )

    //     let difference: SafeFileDifference?

    //     if let existingData,
    //        let oldString = String(data: existingData, encoding: .utf8),
    //        let newString = String(data: incomingData, encoding: .utf8) {
    //         difference = makeStructuredLineDiff(
    //             old: oldString,
    //             new: newString,
    //             oldName: "\(url.lastPathComponent) (existing)",
    //             newName: "\(url.lastPathComponent) (incoming)"
    //         )
    //     } else {
    //         difference = nil
    //     }

    //     return .init(
    //         url: url,
    //         difference: difference
    //     )
    // }

    // private func overwriteConflict(
    //     incomingString: String,
    //     encoding: String.Encoding
    // ) -> SafeFileOverwriteConflict {
    //     let oldString = try? String(
    //         contentsOf: url,
    //         encoding: encoding
    //     )

    //     let difference = oldString.map {
    //         makeStructuredLineDiff(
    //             old: $0,
    //             new: incomingString,
    //             oldName: "\(url.lastPathComponent) (existing)",
    //             newName: "\(url.lastPathComponent) (incoming)"
    //         )
    //     }

    //     return .init(
    //         url: url,
    //         difference: difference
    //     )
    // }
}

// public struct StandardWriter: Sendable, SafelyWritable {
//     public let url: URL

//     public init(
//         _ url: URL
//     ) { 
//         self.url = url
//     }

//     @discardableResult
//     public func write(_ data: Data, options: SafeWriteOptions = .init()) throws -> SafeWriteResult {
//         do {
//             try ensureParentExists(createIfNeeded: options.createIntermediateDirectories)

//             let fm = FileManager.default
//             var backupURL: URL? = nil
//             var overwritten = false

//             if fm.fileExists(atPath: url.path) {
//                 let isBlank = try fileIsBlank(whitespaceCounts: options.whitespaceOnlyIsBlank)

//                 if !isBlank {
//                     switch options.existingFilePolicy {
//                     case .abort:
//                         throw SafeFileError.fileExistsAndNotBlank(url)

//                     case .overwrite:
//                         overwritten = true

//                         if options.makeBackupOnOverride {
//                             if options.createBackupDirectory {
//                                 let ts = timestampString()
//                                 let setDir = try ensureBackupSetDir(options: options, timestamp: ts)
//                                 let dst = setDir.appendingPathComponent(url.lastPathComponent, isDirectory: false)
//                                 try? fm.removeItem(at: dst)
//                                 try fm.copyItem(at: url, to: dst)
//                                 backupURL = dst

//                                 try pruneBackupSets(
//                                     baseDir: setDir.deletingLastPathComponent(),
//                                     prefix: options.backupSetPrefix,
//                                     keep: options.maxBackupSets
//                                 )
//                             } else {
//                                 backupURL = try makeBackup(
//                                     suffix: options.backupSuffix,
//                                     addTimestampIfExists: options.addTimestampIfBackupExists
//                                 )
//                             }
//                         }
//                     }
//                 }
//             }

//             let writeOpts: Data.WritingOptions = options.atomic ? [.atomic] : []
//             try data.write(to: url, options: writeOpts)

//             return .init(
//                 target: url,
//                 wrote: true,
//                 backupURL: backupURL,
//                 overwrittenExisting: overwritten,
//                 bytesWritten: data.count
//             )
//         } catch let e as SafeFileError {
//             throw e
//         } catch {
//             throw SafeFileError.io(underlying: error)
//         }
//     }

//     @discardableResult
//     public func write(
//         _ string: String,
//         encoding: String.Encoding = .utf8,
//         options: SafeWriteOptions = .init()
//     ) throws -> SafeWriteResult {
//         guard let data = string.data(using: encoding) else {
//             throw SafeFileError.io(underlying: NSError(
//                 domain: "SafeFile",
//                 code: -1,
//                 userInfo: [NSLocalizedDescriptionKey: "String encoding failed"]
//             ))
//         }
//         return try write(data, options: options)
//     }

//     @discardableResult
//     public func write(
//         _ string: String,
//         content mode: ContentOverwriteMode,
//         separator: String? = nil,
//         encoding: String.Encoding = .utf8,
//         options: SafeWriteOptions = .init()
//     ) throws -> SafeWriteResult {
//         switch mode {
//         case .replace:
//             return try write(string, encoding: encoding, options: options)

//         case .append:
//             let fm = FileManager.default
//             var composed = string

//             if fm.fileExists(atPath: url.path) {
//                 let isBlank = try fileIsBlank(whitespaceCounts: options.whitespaceOnlyIsBlank)

//                 if !isBlank {
//                     let existingData = try Data(contentsOf: url)

//                     guard let existing = String(data: existingData, encoding: encoding) else {
//                         throw SafeFileError.io(underlying: NSError(
//                             domain: "SafeFile",
//                             code: -2,
//                             userInfo: [NSLocalizedDescriptionKey: "Existing file string decoding failed"]
//                         ))
//                     }

//                     if let separator, !separator.isEmpty {
//                         composed = existing + separator + string
//                     } else {
//                         composed = existing + string
//                     }
//                 }
//             }

//             var writeOptions = options
//             writeOptions.existingFilePolicy = .overwrite

//             return try write(composed, encoding: encoding, options: writeOptions)
//         }
//     }
// }

// // let file = SafeFile(URL(fileURLWithPath: "/path/to/output.txt"))

// // // 1) Safe write (will throw if non-blank file exists)
// // try file.write("Hello\n")

// // // 2) Override with backup
// // (deprecated): var opts = SafeWriteOptions(overrideExisting: true, makeBackupOnOverride: true)
// // (new): var opts = SafeWriteOptions(existingFilePolicy: .overwrite, makeBackupOnOverride: true)
// // try file.write("Hello new world\n", options: opts)

// // // 3) Show diff against backup
// // let diff = try file.diffAgainstBackup()
// // print(diff)

// // // 4) Restore from backup
// // try file.restoreFromBackup()
