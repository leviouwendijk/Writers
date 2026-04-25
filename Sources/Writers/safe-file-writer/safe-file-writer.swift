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
        let plan = try writePlan(
            data,
            incomingText: nil,
            options: options
        )

        return try plan.execution.apply(
            writer: self,
            options: options,
            conflict: overwriteConflict(
                incomingData: data
            )
        )
    }

    @discardableResult
    public func write(
        _ string: String,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> SafeWriteResult {
        guard let data = string.data(using: encoding) else {
            throw SafeFileError.io(
                underlying: NSError(
                    domain: "SafeFile",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "String encoding failed"
                    ]
                )
            )
        }

        let plan = try writePlan(
            data,
            incomingText: string,
            options: options
        )

        return try plan.execution.apply(
            writer: self,
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

                    if let separator,
                       !separator.isEmpty {
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
    public func execute(
        _ plan: WritePlan,
        options: SafeWriteOptions,
        conflict: @autoclosure () -> SafeFileOverwriteConflict
    ) throws -> SafeWriteResult {
        do {
            try requireExecutionTarget(
                plan
            )

            try plan.validateCurrentState(
                policy: options.stalePlanPolicy
            )

            try ensureParentExists(
                createIfNeeded: options.createIntermediateDirectories
            )

            guard plan.canProceed else {
                throw SafeFileError.overwriteConflict(
                    conflict()
                )
            }

            var backupRecord: WriteBackupRecord?
            if plan.overwriteAction.requiresBackupDecision,
               let existingData = plan.existingData {
                backupRecord = try makeBackupRecord(
                    for: existingData,
                    options: options
                )
            }

            let writeOpts: Data.WritingOptions = options.atomic ? [.atomic] : []

            try plan.incoming.data.write(
                to: url,
                options: writeOpts
            )

            return .init(
                target: url,
                wrote: true,
                backupURL: backupRecord?.storage?.localURL,
                overwrittenExisting: plan.overwriteAction == .overwrite_nonblank,
                bytesWritten: plan.incoming.data.count,
                backupRecord: backupRecord,
                beforeSnapshot: plan.before,
                afterSnapshot: plan.after
            )
        } catch let error as SafeFileError {
            throw error
        } catch {
            throw SafeFileError.io(
                underlying: error
            )
        }
    }

    private func requireExecutionTarget(
        _ plan: WritePlan
    ) throws {
        guard plan.target.standardizedFileURL.path == url.standardizedFileURL.path else {
            throw SafeFileError.io(
                underlying: NSError(
                    domain: "Writers.WriteExecution",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "WriteExecution target mismatch. Plan target: \(plan.target.path). Writer target: \(url.path)."
                    ]
                )
            )
        }
    }

    private func makeBackupRecord(
        for data: Data,
        options: SafeWriteOptions
    ) throws -> WriteBackupRecord? {
        let policy = options.resolvedBackupPolicy

        switch policy {
        case .automatic:
            return nil

        case .disabled:
            return nil

        case .sibling_file:
            let backupURL = try makeBackup(
                suffix: options.backupSuffix,
                addTimestampIfExists: options.addTimestampIfBackupExists
            )

            return .init(
                target: url,
                storage: .local(backupURL),
                originalFingerprint: StandardContentFingerprint.fingerprint(
                    for: data
                ),
                byteCount: data.count,
                policy: policy
            )

        case .backup_directory:
            let ts = timestampString()
            let setDir = try ensureBackupSetDir(
                options: options,
                timestamp: ts
            )
            let dst = setDir.appendingPathComponent(
                url.lastPathComponent,
                isDirectory: false
            )

            try? FileManager.default.removeItem(
                at: dst
            )

            try FileManager.default.copyItem(
                at: url,
                to: dst
            )

            try pruneBackupSets(
                baseDir: setDir.deletingLastPathComponent(),
                prefix: options.backupSetPrefix,
                keep: options.maxBackupSets
            )

            return .init(
                target: url,
                storage: .local(dst),
                originalFingerprint: StandardContentFingerprint.fingerprint(
                    for: data
                ),
                byteCount: data.count,
                policy: policy
            )

        case .external_store:
            guard let backupStore = options.backupStore else {
                throw WriteBackupStoreError.store_required(
                    policy: policy,
                    target: url
                )
            }

            return try backupStore.storeBackup(
                .init(
                    target: url,
                    data: data,
                    policy: policy
                )
            )
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
            difference = WriteDifference.lines(
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
            WriteDifference.lines(
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
}

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
