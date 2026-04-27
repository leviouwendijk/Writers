import Foundation
import Position
import TestFlows
import Writers

enum WritersFlowSuite: TestFlowRegistry {
    static let title = "Writers flow tests"

    static let flows: [TestFlow] = [
        writeMutationFlow,
        backupPolicyFlow,
        backupPruneFlow,
        backupRecordContractFlow,
        externalBackupStoreFlow,
        preflightFlow,
        targetPreflightContractFlow,
        writeContractFlow,
        writeExecutionContractFlow,
        stalePlanContractFlow,
        overwriteConflictFlow,
        editPreviewAndRollbackFlow,
        editRecordStoreFlow,
        recordStorageFlow,
        payloadPolicyContractFlow,
        storageProtocolContractFlow,
        storageLocationContractFlow,
        mutationSurfaceContractFlow,
        rollbackSurfaceContractFlow,
        editMergeFlow,
        mutationRollbackFlow,
        rollbackPlanContractFlow,
        binaryRollbackContractFlow,
        mutationSnapshotFlow,
        editConstraintFlow,
        editBatchFlow,
        editPassFlow,
        standardMutationFlow,
        standardRollbackFlow,
        standardRollbackHardeningFlow,
        writerFacadeFlow,
        workspaceWriterFlow,
    ]
}

private extension WritersFlowSuite {
    static var writeMutationFlow: TestFlow {
        TestFlow(
            "write-mutation",
            tags: ["write", "mutation", "snapshot"]
        ) {
            Step("overwrite records before and after snapshots") {
                let workspace = try TestWorkspace("write-mutation")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "alpha\nbeta\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "alpha\nbravo\n",
                    options: .overwriteWithoutBackup
                )

                let record = result.mutationRecord(
                    operationKind: .write_text
                )

                try Expect.true(
                    result.wrote,
                    "write.result.wrote"
                )
                try Expect.true(
                    result.overwrittenExisting,
                    "write.result.overwritten"
                )
                try Expect.isNil(
                    result.backupRecord,
                    "write.result.backup"
                )
                _ = try Expect.notNil(
                    result.beforeSnapshot,
                    "write.result.before"
                )
                _ = try Expect.notNil(
                    result.afterSnapshot,
                    "write.result.after"
                )
                try Expect.equal(
                    record.operationKind,
                    .write_text,
                    "write.record.operation"
                )
                _ = try Expect.notNil(
                    record.rollbackGuard,
                    "write.record.rollback-guard"
                )
                try Expect.equal(
                    try workspace.read(url),
                    "alpha\nbravo\n",
                    "write.file.content"
                )
            }
        }
    }

    static var backupPolicyFlow: TestFlow {
        TestFlow(
            "backup-policy",
            tags: ["write", "backup"]
        ) {
            Step("backup directory policy stores overwritten content") {
                let workspace = try TestWorkspace("backup-policy")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "old\ncontent\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "new\ncontent\n",
                    options: .overwriting(
                        backupPolicy: .backup_directory,
                        maxBackupSets: 10
                    )
                )

                let backup = try Expect.notNil(
                    result.backupRecord,
                    "backup.record"
                )
                let backupURL = try Expect.notNil(
                    backup.storage?.localURL,
                    "backup.url"
                )

                try Expect.equal(
                    backup.policy,
                    .backup_directory,
                    "backup.policy"
                )
                try Expect.true(
                    workspace.exists(backupURL),
                    "backup.exists"
                )
                try Expect.equal(
                    try workspace.read(backupURL),
                    "old\ncontent\n",
                    "backup.content"
                )
                try Expect.equal(
                    try workspace.read(url),
                    "new\ncontent\n",
                    "backup.target.content"
                )
            }
        }
    }

    static var externalBackupStoreFlow: TestFlow {
        TestFlow(
            "external-backup-store",
            tags: ["write", "backup", "external-store"]
        ) {
            Step("external store receives overwritten content") {
                let workspace = try TestWorkspace("external-backup-store")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let store = DirectoryBackupStore(
                    root: try workspace.directory(
                        "external-backups"
                    )
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "stored before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "stored after\n",
                    options: .overwriting(
                        backupPolicy: .external_store,
                        backupStore: store,
                        maxBackupSets: nil
                    )
                )

                let backup = try Expect.notNil(
                    result.backupRecord,
                    "external.backup.record"
                )

                try Expect.equal(
                    backup.policy,
                    .external_store,
                    "external.backup.policy"
                )

                let data = try Expect.notNil(
                    try store.loadBackup(
                        backup
                    ),
                    "external.backup.data"
                )

                try Expect.equal(
                    String(
                        decoding: data,
                        as: UTF8.self
                    ),
                    "stored before\n",
                    "external.backup.content"
                )

                try Expect.equal(
                    try workspace.read(url),
                    "stored after\n",
                    "external.target.content"
                )
            }

            Step("external store policy requires a store") {
                let workspace = try TestWorkspace("external-backup-store-required")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "external.store.required"
                ) {
                    _ = try writer.write(
                        "after\n",
                        options: .overwriting(
                            backupPolicy: .external_store,
                            backupStore: nil,
                            maxBackupSets: nil
                        )
                    )
                }
            }
        }
    }

    static var overwriteConflictFlow: TestFlow {
        TestFlow(
            "overwrite-conflict",
            tags: ["write", "conflict"]
        ) {
            Step("default write refuses non-blank overwrite") {
                let workspace = try TestWorkspace("overwrite-conflict")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "existing\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "overwrite.conflict"
                ) {
                    _ = try writer.write(
                        "incoming\n"
                    )
                }

                try Expect.equal(
                    try workspace.read(url),
                    "existing\n",
                    "overwrite.conflict.content-preserved"
                )
            }
        }
    }

    static var editPreviewAndRollbackFlow: TestFlow {
        TestFlow(
            "edit-preview-and-rollback",
            tags: ["edit", "preview", "rollback"]
        ) {
            Step("preview does not write") {
                let workspace = try TestWorkspace("edit-preview")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "alpha\nbeta\ngamma\n",
                    options: .overwriteWithoutBackup
                )

                let preview = try writer.editor.preview(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    )
                )

                try Expect.true(
                    preview.hasChanges,
                    "edit.preview.has-changes"
                )
                try Expect.false(
                    preview.performedWrite,
                    "edit.preview.performed-write"
                )
                try Expect.equal(
                    preview.editedContent,
                    "alpha\nbravo\ngamma\n",
                    "edit.preview.edited-content"
                )
                try Expect.equal(
                    try workspace.read(url),
                    "alpha\nbeta\ngamma\n",
                    "edit.preview.target-unchanged"
                )
            }

            Step("edit writes and rollback operations restore content") {
                let workspace = try TestWorkspace("edit-rollback")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let original = "alpha\nbeta\ngamma\n"
                let edited = "alpha\nbravo\ngamma\n"

                _ = try writer.write(
                    original,
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    ),
                    options: .overwriteWithoutBackup
                )

                let record = edit.record()

                try Expect.true(
                    edit.performedWrite,
                    "edit.performed-write"
                )
                try Expect.equal(
                    edit.editedContent,
                    edited,
                    "edit.edited-content"
                )
                try Expect.equal(
                    try workspace.read(url),
                    edited,
                    "edit.target-content"
                )
                try Expect.true(
                    record.canRollback(
                        from: edit.editedContent
                    ),
                    "edit.record.can-rollback"
                )
                try Expect.equal(
                    edit.rollbackOperations.count,
                    1,
                    "edit.rollback-operation-count"
                )

                _ = try writer.editor.edit(
                    edit.rollbackOperations,
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    try workspace.read(url),
                    original,
                    "edit.rollback.restored"
                )
            }
        }
    }

    static var mutationSnapshotFlow: TestFlow {
        TestFlow(
            "mutation-snapshot",
            tags: ["mutation", "snapshot"]
        ) {
            Step("snapshot normalized write mutation summary") {
                let workspace = try TestWorkspace("mutation-snapshot-write")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "after\n",
                    options: .overwriteWithoutBackup
                )

                let summary = try MutationSummary(
                    result.mutationRecord(
                        operationKind: .write_text
                    )
                ).render()

                try Expect.snapshot(
                    summary,
                    named: "write-mutation-summary"
                )
            }

            Step("snapshot normalized edit mutation summary") {
                let workspace = try TestWorkspace("mutation-snapshot-edit")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "alpha\nbeta\ngamma\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    [
                        .replaceUnique(
                            of: "beta",
                            with: "bravo"
                        ),
                        .append(
                            "delta",
                            separator: "\n"
                        ),
                    ],
                    options: .overwriteWithoutBackup
                )

                let summary = try MutationSummary(
                    edit.mutationRecord(
                        operationKind: .edit_operations,
                        storeContent: false
                    )
                ).render()

                try Expect.snapshot(
                    summary,
                    named: "edit-mutation-summary"
                )
            }
        }
    }

    static var backupPruneFlow: TestFlow {
        TestFlow(
            "backup-prune",
            tags: ["backup", "retention"]
        ) {
            Step("prune backup sets keeps latest directories") {
                let workspace = try TestWorkspace("backup-prune")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .backup_directory,
                    maxBackupSets: 2
                )
                let base = writer.backupBaseDir(
                    options: options
                )

                try FileManager.default.createDirectory(
                    at: base,
                    withIntermediateDirectories: true
                )

                for name in [
                    "overwrite_001",
                    "overwrite_002",
                    "overwrite_003",
                    "other_001",
                ] {
                    try FileManager.default.createDirectory(
                        at: base.appendingPathComponent(
                            name,
                            isDirectory: true
                        ),
                        withIntermediateDirectories: true
                    )
                }

                try writer.pruneBackupSets(
                    baseDir: base,
                    prefix: options.backupSetPrefix,
                    keep: 2
                )

                let names = try FileManager.default.contentsOfDirectory(
                    at: base,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                .map(\.lastPathComponent)
                .sorted()

                try Expect.equal(
                    names,
                    [
                        "other_001",
                        "overwrite_002",
                        "overwrite_003",
                    ],
                    "backup.prune.names"
                )
            }
        }
    }

    static var preflightFlow: TestFlow {
        TestFlow(
            "preflight",
            tags: ["write", "preflight", "backup"]
        ) {
            Step("preflight refuses non-blank overwrite with abort policy") {
                let workspace = try TestWorkspace("preflight-abort")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "existing\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "preflight.abort"
                ) {
                    try preflightSafeWrite(
                        [
                            url
                        ],
                        options: .init(
                            existingFilePolicy: .abort
                        )
                    )
                }

                try Expect.equal(
                    try workspace.read(url),
                    "existing\n",
                    "preflight.abort.content-preserved"
                )
            }

            Step("preflight overwrite creates sibling backup without mutating target") {
                let workspace = try TestWorkspace("preflight-sibling")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "existing\n",
                    options: .overwriteWithoutBackup
                )

                let result = try WriteTargetPreflight.prepare(
                    [
                        url,
                    ],
                    options: .overwriting(
                        backupPolicy: .sibling_file,
                        maxBackupSets: nil
                    )
                )

                let backup = try Expect.notNil(
                    result.backupRecords.first,
                    "preflight.sibling.backup-record"
                )

                let backupURL = try Expect.notNil(
                    backup.storage?.localURL,
                    "preflight.sibling.backup-url"
                )

                try Expect.true(
                    workspace.exists(backupURL),
                    "preflight.sibling.backup-exists"
                )
                try Expect.equal(
                    try workspace.read(backupURL),
                    "existing\n",
                    "preflight.sibling.backup-content"
                )
                try Expect.equal(
                    try workspace.read(url),
                    "existing\n",
                    "preflight.sibling.target-content"
                )
            }

            Step("preflight external store policy requires store") {
                let workspace = try TestWorkspace("preflight-external-required")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "existing\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "preflight.external-store.required"
                ) {
                    _ = try WriteTargetPreflight.prepare(
                        [
                            url,
                        ],
                        options: .overwriting(
                            backupPolicy: .external_store,
                            backupStore: nil,
                            maxBackupSets: nil
                        )
                    )
                }
            }
        }
    }

    static var editRecordStoreFlow: TestFlow {
        TestFlow(
            "edit-record-store",
            tags: ["edit", "record", "store", "rollback"]
        ) {
            Step("save and load edit record preserves rollback metadata") {
                let workspace = try TestWorkspace("edit-record-store")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "alpha\nbeta\ngamma\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.preview(
                    [
                        .replaceUnique(
                            of: "beta",
                            with: "bravo"
                        ),
                        .append(
                            "delta",
                            separator: "\n"
                        ),
                    ]
                )

                let record = edit.record()
                let store = StandardEditRecordStore(
                    directoryURL: try workspace.directory(
                        "edit-records"
                    )
                )

                let savedURL = try store.save(
                    record
                )
                let loaded = try store.load(
                    savedURL
                )

                try Expect.equal(
                    loaded.id,
                    record.id,
                    "edit.record.id"
                )
                try Expect.equal(
                    loaded.target.lastPathComponent,
                    "sample.txt",
                    "edit.record.target"
                )
                try Expect.equal(
                    loaded.operations.count,
                    2,
                    "edit.record.operation-count"
                )
                try Expect.equal(
                    loaded.changes.count,
                    record.changes.count,
                    "edit.record.change-count"
                )
                try Expect.true(
                    loaded.canApplyForward(
                        to: "alpha\nbeta\ngamma\n"
                    ),
                    "edit.record.can-apply-forward"
                )
                try Expect.true(
                    loaded.canRollback(
                        from: edit.editedContent
                    ),
                    "edit.record.can-rollback"
                )
                try Expect.equal(
                    loaded.rollbackOperations.count,
                    record.rollbackOperations.count,
                    "edit.record.rollback-count"
                )
            }
        }
    }

    static var editMergeFlow: TestFlow {
        TestFlow(
            "edit-merge",
            tags: ["edit", "merge", "drift"]
        ) {
            Step("merge uses replaceFromBase when current still matches original") {
                let workspace = try TestWorkspace("merge-replace-from-base")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let original = "alpha\nbeta\ngamma\n"
                let edited = "alpha\nbravo\ngamma\n"

                _ = try writer.write(
                    original,
                    options: .overwriteWithoutBackup
                )

                let record = try writer.editor.preview(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    )
                )
                .record()

                let merge = try StandardEditMerger(
                    record: record,
                    writer: writer
                )
                .preview(
                    currentContent: original
                )

                try Expect.equal(
                    merge.strategy,
                    .replaceFromBase,
                    "merge.replace-from-base.strategy"
                )
                try Expect.equal(
                    merge.mergedContent,
                    edited,
                    "merge.replace-from-base.content"
                )
            }

            Step("merge detects already applied content") {
                let workspace = try TestWorkspace("merge-already-applied")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let original = "alpha\nbeta\ngamma\n"
                let edited = "alpha\nbravo\ngamma\n"

                _ = try writer.write(
                    original,
                    options: .overwriteWithoutBackup
                )

                let record = try writer.editor.preview(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    )
                )
                .record()

                let merge = try StandardEditMerger(
                    record: record,
                    writer: writer
                )
                .preview(
                    currentContent: edited
                )

                try Expect.equal(
                    merge.strategy,
                    .alreadyApplied,
                    "merge.already-applied.strategy"
                )
                try Expect.equal(
                    merge.mergedContent,
                    edited,
                    "merge.already-applied.content"
                )
            }

            Step("merge replays anchors after unrelated drift") {
                let workspace = try TestWorkspace("merge-replay-anchors")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let original = "alpha\nbeta\ngamma\n"
                let drifted = "prefix\nalpha\nbeta\ngamma\n"
                let merged = "prefix\nalpha\nbravo\ngamma\n"

                _ = try writer.write(
                    original,
                    options: .overwriteWithoutBackup
                )

                let record = try writer.editor.preview(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    )
                )
                .record()

                let merge = try StandardEditMerger(
                    record: record,
                    writer: writer
                )
                .preview(
                    currentContent: drifted
                )

                try Expect.equal(
                    merge.strategy,
                    .replayAnchors,
                    "merge.replay-anchors.strategy"
                )
                try Expect.equal(
                    merge.mergedContent,
                    merged,
                    "merge.replay-anchors.content"
                )
            }

            Step("merge blocks conflicting drift") {
                let workspace = try TestWorkspace("merge-conflict")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let original = "alpha\nbeta\ngamma\n"
                let conflicting = "alpha\nbeeta\ngamma\n"

                _ = try writer.write(
                    original,
                    options: .overwriteWithoutBackup
                )

                let record = try writer.editor.preview(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    )
                )
                .record()

                try Expect.throwsError(
                    "merge.conflict"
                ) {
                    _ = try StandardEditMerger(
                        record: record,
                        writer: writer
                    )
                    .preview(
                        currentContent: conflicting
                    )
                }
            }
        }
    }

    static var mutationRollbackFlow: TestFlow {
        TestFlow(
            "mutation-rollback",
            tags: ["mutation", "rollback", "guard"]
        ) {
            Step("rollback restores before snapshot content") {
                let workspace = try TestWorkspace("mutation-rollback-snapshot")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let original = "alpha\nbeta\ngamma\n"
                let edited = "alpha\nbravo\ngamma\n"

                _ = try writer.write(
                    original,
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    ),
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    try workspace.read(url),
                    edited,
                    "rollback.snapshot.edited-content"
                )

                let record = edit.mutationRecord(
                    operationKind: .edit_operations,
                    storeContent: true
                )

                let preview = try writer.previewRollback(
                    record
                )

                try Expect.equal(
                    preview.strategy,
                    .before_snapshot,
                    "rollback.snapshot.strategy"
                )
                try Expect.equal(
                    preview.rollbackContent,
                    original,
                    "rollback.snapshot.preview-content"
                )

                let result = try writer.rollback(
                    record,
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    try workspace.read(url),
                    original,
                    "rollback.snapshot.restored"
                )
                try Expect.equal(
                    result.rollbackRecord.operationKind,
                    .rollback,
                    "rollback.snapshot.record-kind"
                )
                try Expect.equal(
                    result.rollbackRecord.metadata["rollback_of"],
                    record.id.uuidString.lowercased(),
                    "rollback.snapshot.record-link"
                )
            }

            Step("rollback operations work without stored content") {
                let workspace = try TestWorkspace("mutation-rollback-operations")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let original = "alpha\nbeta\ngamma\n"
                let edited = "alpha\nbravo\ngamma\n"

                _ = try writer.write(
                    original,
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    ),
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    try workspace.read(url),
                    edited,
                    "rollback.operations.edited-content"
                )

                let record = edit.mutationRecord(
                    operationKind: .edit_operations,
                    storeContent: false
                )

                let preview = try writer.previewRollback(
                    record
                )

                try Expect.equal(
                    preview.strategy,
                    .rollback_operations,
                    "rollback.operations.strategy"
                )
                try Expect.equal(
                    preview.rollbackContent,
                    original,
                    "rollback.operations.preview-content"
                )

                _ = try writer.rollback(
                    record,
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    try workspace.read(url),
                    original,
                    "rollback.operations.restored"
                )
            }

            Step("rollback guard blocks drifted current content") {
                let workspace = try TestWorkspace("mutation-rollback-guard")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "alpha\nbeta\ngamma\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    ),
                    options: .overwriteWithoutBackup
                )

                let record = edit.mutationRecord(
                    operationKind: .edit_operations,
                    storeContent: true
                )

                _ = try writer.write(
                    "alpha\ndrift\ngamma\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "rollback.guard.drift"
                ) {
                    _ = try writer.rollback(
                        record,
                        options: .overwriteWithoutBackup
                    )
                }

                try Expect.equal(
                    try workspace.read(url),
                    "alpha\ndrift\ngamma\n",
                    "rollback.guard.content-preserved"
                )
            }

            Step("write mutation without content payload cannot rollback") {
                let workspace = try TestWorkspace("mutation-rollback-missing-payload")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "after\n",
                    options: .overwriteWithoutBackup
                )

                let record = result.mutationRecord(
                    operationKind: .write_text
                )

                try Expect.false(
                    record.hasRollbackPayload,
                    "rollback.missing-payload.has-payload"
                )

                try Expect.throwsError(
                    "rollback.missing-payload"
                ) {
                    _ = try writer.rollback(
                        record,
                        options: .overwriteWithoutBackup
                    )
                }

                try Expect.equal(
                    try workspace.read(url),
                    "after\n",
                    "rollback.missing-payload.content-preserved"
                )
            }
        }
    }

    static var recordStorageFlow: TestFlow {
        TestFlow(
            "record-storage",
            tags: ["record", "storage", "mutation", "edit"]
        ) {
            Step("local mutation record store saves, loads, queries, and deletes records") {
                let workspace = try TestWorkspace("mutation-record-storage")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "after\n",
                    options: .overwriteWithoutBackup
                )

                let record = result.mutationRecord(
                    operationKind: .write_text,
                    metadata: [
                        WriteMutationMetadataKey.resource_change: WriteResourceChangeKind.update
                            .rawValue,
                        WriteMutationMetadataKey.delta_kind: WriteDeltaKind.replacement.rawValue,
                    ]
                )

                let store = WriteRecords.local.mutations(
                    directory: try workspace.directory(
                        "mutation-records"
                    )
                )

                let stored = try store.records.save(
                    record
                )

                let location = try Expect.notNil(
                    stored.storage?.localURL,
                    "record.storage.mutation.local-url"
                )

                try Expect.true(
                    workspace.exists(location),
                    "record.storage.mutation.file-exists"
                )

                let loaded = try Expect.notNil(
                    try store.records.load(
                        stored
                    ),
                    "record.storage.mutation.loaded"
                )

                try Expect.equal(
                    loaded.id,
                    record.id,
                    "record.storage.mutation.id"
                )

                try Expect.equal(
                    loaded.surface.resource,
                    .update,
                    "record.storage.mutation.surface.resource"
                )

                try Expect.equal(
                    loaded.surface.delta,
                    .replacement,
                    "record.storage.mutation.surface.delta"
                )

                try Expect.equal(
                    try store.records.list().count,
                    1,
                    "record.storage.mutation.list-count"
                )

                let loadedByID = try Expect.notNil(
                    try store.records.load(
                        record.id
                    ),
                    "record.storage.mutation.loaded-by-id"
                )

                try Expect.equal(
                    loadedByID.id,
                    record.id,
                    "record.storage.mutation.loaded-by-id.id"
                )

                try Expect.equal(
                    try store.records.list(
                        .target(
                            url
                        )
                    ).count,
                    1,
                    "record.storage.mutation.query-target-count"
                )

                try store.records.delete(
                    stored
                )

                try Expect.equal(
                    try store.records.list().count,
                    0,
                    "record.storage.mutation.delete-count"
                )
            }

            Step("local edit record store saves, loads, queries, and deletes records") {
                let workspace = try TestWorkspace("edit-record-storage")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "alpha\nbeta\ngamma\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.preview(
                    [
                        .replaceUnique(
                            of: "beta",
                            with: "bravo"
                        ),
                        .append(
                            "delta",
                            separator: "\n"
                        ),
                    ]
                )

                let record = edit.record()
                let store = WriteRecords.local.edits(
                    directory: try workspace.directory(
                        "edit-records"
                    )
                )

                let stored = try store.records.save(
                    record
                )

                let location = try Expect.notNil(
                    stored.storage?.localURL,
                    "record.storage.edit.local-url"
                )

                try Expect.true(
                    workspace.exists(location),
                    "record.storage.edit.file-exists"
                )

                let loaded = try Expect.notNil(
                    try store.records.load(
                        stored
                    ),
                    "record.storage.edit.loaded"
                )

                try Expect.equal(
                    loaded.id,
                    record.id,
                    "record.storage.edit.id"
                )

                try Expect.equal(
                    loaded.rollbackOperations.count,
                    record.rollbackOperations.count,
                    "record.storage.edit.rollback-operation-count"
                )

                try Expect.equal(
                    try store.records.list().count,
                    1,
                    "record.storage.edit.list-count"
                )

                let loadedByID = try Expect.notNil(
                    try store.records.load(
                        record.id
                    ),
                    "record.storage.edit.loaded-by-id"
                )

                try Expect.equal(
                    loadedByID.id,
                    record.id,
                    "record.storage.edit.loaded-by-id.id"
                )

                try Expect.equal(
                    try store.records.list(
                        .target(
                            url
                        )
                    ).count,
                    1,
                    "record.storage.edit.query-target-count"
                )

                try store.records.delete(
                    stored
                )

                try Expect.equal(
                    try store.records.list().count,
                    0,
                    "record.storage.edit.delete-count"
                )
            }

            Step("record store rejects mismatched record kind") {
                let workspace = try TestWorkspace("record-storage-kind-mismatch")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "content\n",
                    options: .overwriteWithoutBackup
                )

                let record = try writer.editor.preview(
                    .replaceUnique(
                        of: "content",
                        with: "changed"
                    )
                )
                .record()

                let editStore = WriteRecords.local.edits(
                    directory: try workspace.directory(
                        "edit-records"
                    )
                )

                let stored = try editStore.records.save(
                    record
                )

                let mutationStore = WriteRecords.local.mutations(
                    directory: try workspace.directory(
                        "mutation-records"
                    )
                )

                try Expect.throwsError(
                    "record.storage.kind-mismatch"
                ) {
                    _ = try mutationStore.records.load(
                        stored
                    )
                }
            }
        }
    }

    static var storageLocationContractFlow: TestFlow {
        TestFlow(
            "storage-location-contract",
            tags: ["storage", "backup", "record", "contract"]
        ) {
            Step("local storage location round trips as local URL") {
                let workspace = try TestWorkspace("storage-location-local")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "stored.json"
                )

                let location = WriteStorageLocation.local(
                    url
                )

                try Expect.equal(
                    location.kind,
                    .local_file,
                    "storage.location.kind"
                )
                try Expect.equal(
                    location.localURL?.standardizedFileURL.path,
                    url.standardizedFileURL.path,
                    "storage.location.local-url"
                )
            }

            Step("external storage location does not pretend to be local") {
                let location = WriteStorageLocation(
                    kind: .external,
                    value: "agentic://records/abc",
                    metadata: [
                        "store": "agentic"
                    ]
                )

                try Expect.isNil(
                    location.localURL,
                    "storage.location.external.local-url"
                )

                let stored = WriteStoredRecord(
                    id: UUID(),
                    kind: .mutation,
                    target: URL(
                        fileURLWithPath: "/tmp/sample.txt"
                    ),
                    storage: location
                )

                try Expect.throwsError(
                    "storage.location.external.require-local"
                ) {
                    _ = try stored.requireLocalURL()
                }
            }

            Step("backup records expose storage while keeping backupURL bridge") {
                let workspace = try TestWorkspace("backup-storage-location")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "after\n",
                    options: .overwriting(
                        backupPolicy: .sibling_file
                    )
                )

                let backup = try Expect.notNil(
                    result.backupRecord,
                    "backup.storage.record"
                )

                let backupURL = try Expect.notNil(
                    backup.storage?.localURL,
                    "backup.storage.local-url"
                )

                let legacyJSON = """
                {
                    "id": "\(backup.id.uuidString)",
                    "target": "\(backup.target.absoluteString)",
                    "backupURL": "\(backupURL.absoluteString)",
                    "createdAt": "2026-04-25T00:00:00Z",
                    "originalFingerprint": {
                        "algorithm": "\(backup.originalFingerprint.algorithm)",
                        "value": "\(backup.originalFingerprint.value)"
                    },
                    "byteCount": \(backup.byteCount),
                    "policy": "\(backup.policy.rawValue)",
                    "metadata": {}
                }
                """

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let legacyDecoded = try decoder.decode(
                    WriteBackupRecord.self,
                    from: Data(
                        legacyJSON.utf8
                    )
                )

                try Expect.equal(
                    legacyDecoded.storage?.localURL?.standardizedFileURL.path,
                    backupURL.standardizedFileURL.path,
                    "backup.storage.legacy-url"
                )
            }
        }
    }

    static var mutationSurfaceContractFlow: TestFlow {
        TestFlow(
            "mutation-surface-contract",
            tags: ["mutation", "surface", "metadata", "contract"]
        ) {
            Step("explicit metadata overrides computed classification") {
                let target = URL(
                    fileURLWithPath: "/tmp/surface.txt"
                )

                let record = WriteMutationRecord(
                    target: target,
                    operationKind: .write_text,
                    before: .init(
                        content: "a",
                        storeContent: true
                    ),
                    after: .init(
                        content: "b",
                        storeContent: true
                    ),
                    metadata: [
                        WriteMutationMetadataKey.resource_change: WriteResourceChangeKind.creation
                            .rawValue,
                        WriteMutationMetadataKey.delta_kind: WriteDeltaKind.addition.rawValue,
                    ]
                )

                try Expect.equal(
                    record.resourceChangeKind,
                    .update,
                    "mutation.surface.computed.resource"
                )
                try Expect.equal(
                    record.deltaKind,
                    .replacement,
                    "mutation.surface.computed.delta"
                )
                try Expect.equal(
                    record.surface.resource,
                    .creation,
                    "mutation.surface.stored.resource"
                )
                try Expect.equal(
                    record.surface.delta,
                    .addition,
                    "mutation.surface.stored.delta"
                )
            }

            Step("malformed metadata falls back to computed classification") {
                let record = WriteMutationRecord(
                    target: URL(
                        fileURLWithPath: "/tmp/surface.txt"
                    ),
                    operationKind: .write_text,
                    before: nil,
                    after: .init(
                        content: "created",
                        storeContent: true
                    ),
                    metadata: [
                        WriteMutationMetadataKey.resource_change: "bad",
                        WriteMutationMetadataKey.delta_kind: "bad",
                    ]
                )

                try Expect.equal(
                    record.surface.resource,
                    .creation,
                    "mutation.surface.fallback.resource"
                )
                try Expect.equal(
                    record.surface.delta,
                    .addition,
                    "mutation.surface.fallback.delta"
                )
            }

            Step("typed metadata writes raw metadata safely") {
                let rollbackOf = UUID()
                var metadata = WriteMutationMetadata()
                metadata.rollbackOf = rollbackOf
                metadata.rollbackStrategy = .before_snapshot
                metadata.resource = .update
                metadata.delta = .replacement

                let record = WriteMutationRecord(
                    target: URL(
                        fileURLWithPath: "/tmp/surface.txt"
                    ),
                    operationKind: .rollback,
                    metadata: metadata.raw
                )

                try Expect.equal(
                    record.surface.rollback.of,
                    rollbackOf,
                    "mutation.surface.rollback.of"
                )
                try Expect.equal(
                    record.surface.rollback.strategy,
                    .before_snapshot,
                    "mutation.surface.rollback.strategy"
                )
                try Expect.equal(
                    record.surface.resource,
                    .update,
                    "mutation.surface.metadata.resource"
                )
                try Expect.equal(
                    record.surface.delta,
                    .replacement,
                    "mutation.surface.metadata.delta"
                )
            }
        }
    }

    static var writeContractFlow: TestFlow {
        TestFlow(
            "write-contract",
            tags: ["write", "preflight", "plan", "contract"]
        ) {
            Step("write plan predicts creation") {
                let workspace = try TestWorkspace("write-plan-creation")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                let plan = try writer.preflight.string(
                    "created\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.true(
                    plan.canProceed,
                    "write.plan.creation.can-proceed"
                )
                try Expect.equal(
                    plan.resource,
                    .creation,
                    "write.plan.creation.resource"
                )
                try Expect.equal(
                    plan.delta,
                    .addition,
                    "write.plan.creation.delta"
                )
                try Expect.false(
                    plan.hasCollision,
                    "write.plan.creation.collision"
                )

                let result = try writer.write(
                    "created\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.false(
                    result.overwrittenExisting,
                    "write.plan.creation.actual-overwrite"
                )
                try Expect.equal(
                    result.afterSnapshot?.fingerprint,
                    plan.after.fingerprint,
                    "write.plan.creation.after-fingerprint"
                )
            }

            Step("write plan predicts aborting overwrite collision") {
                let workspace = try TestWorkspace("write-plan-abort")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let plan = try writer.preflight.string(
                    "after\n",
                    options: .init(
                        existingFilePolicy: .abort
                    )
                )

                try Expect.false(
                    plan.canProceed,
                    "write.plan.abort.can-proceed"
                )
                try Expect.true(
                    plan.hasCollision,
                    "write.plan.abort.collision"
                )
                try Expect.equal(
                    plan.resource,
                    .update,
                    "write.plan.abort.resource"
                )
                try Expect.equal(
                    plan.delta,
                    .replacement,
                    "write.plan.abort.delta"
                )

                try Expect.throwsError(
                    "write.plan.abort.require-clean"
                ) {
                    _ = try plan.requireClean()
                }

                try Expect.throwsError(
                    "write.plan.abort.actual-write"
                ) {
                    _ = try writer.write(
                        "after\n",
                        options: .init(
                            existingFilePolicy: .abort
                        )
                    )
                }
            }

            Step("write plan predicts overwrite result") {
                let workspace = try TestWorkspace("write-plan-overwrite")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let plan = try writer.preflight.string(
                    "after\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.true(
                    plan.canProceed,
                    "write.plan.overwrite.can-proceed"
                )
                try Expect.true(
                    plan.hasCollision,
                    "write.plan.overwrite.collision"
                )
                try Expect.equal(
                    plan.resource,
                    .update,
                    "write.plan.overwrite.resource"
                )
                try Expect.equal(
                    plan.delta,
                    .replacement,
                    "write.plan.overwrite.delta"
                )

                let result = try writer.write(
                    "after\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.true(
                    result.overwrittenExisting,
                    "write.plan.overwrite.actual-overwrite"
                )
                try Expect.equal(
                    result.beforeSnapshot?.fingerprint,
                    plan.before?.fingerprint,
                    "write.plan.overwrite.before-fingerprint"
                )
                try Expect.equal(
                    result.afterSnapshot?.fingerprint,
                    plan.after.fingerprint,
                    "write.plan.overwrite.after-fingerprint"
                )
            }
        }
    }

    static var writeExecutionContractFlow: TestFlow {
        TestFlow(
            "write-execution-contract",
            tags: ["write", "plan", "execution"]
        ) {
            Step("write plan and write result share snapshots") {
                let workspace = try TestWorkspace("write-execution-snapshots")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let plan = try writer.preflight.string(
                    "after\n",
                    options: .overwriteWithoutBackup
                )

                let result = try plan.execution.apply(
                    writer: writer,
                    options: .overwriteWithoutBackup,
                    conflict: SafeFileOverwriteConflict(
                        url: url,
                        difference: nil
                    )
                )

                try Expect.equal(
                    result.beforeSnapshot?.fingerprint,
                    plan.before?.fingerprint,
                    "execution.before-fingerprint"
                )
                try Expect.equal(
                    result.afterSnapshot?.fingerprint,
                    plan.after.fingerprint,
                    "execution.after-fingerprint"
                )
                try Expect.equal(
                    try workspace.read(url),
                    "after\n",
                    "execution.content"
                )
            }

            Step("abort plan does not write or backup") {
                let workspace = try TestWorkspace("write-execution-abort")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let options = SafeWriteOptions(
                    existingFilePolicy: .abort,
                    backupPolicy: .sibling_file
                )

                let plan = try writer.preflight.string(
                    "after\n",
                    options: options
                )

                try Expect.equal(
                    plan.overwriteAction,
                    .abort_collision,
                    "execution.abort.action"
                )

                try Expect.throwsError(
                    "execution.abort"
                ) {
                    _ = try plan.execution.apply(
                        writer: writer,
                        options: options,
                        conflict: SafeFileOverwriteConflict(
                            url: url,
                            difference: nil
                        )
                    )
                }

                try Expect.equal(
                    try workspace.read(url),
                    "before\n",
                    "execution.abort.content"
                )
            }

            Step("nonblank overwrite creates one backup from execution") {
                let workspace = try TestWorkspace("write-execution-backup-once")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .backup_directory,
                    maxBackupSets: 10
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let plan = try writer.preflight.string(
                    "after\n",
                    options: options
                )

                let result = try plan.execution.apply(
                    writer: writer,
                    options: options,
                    conflict: SafeFileOverwriteConflict(
                        url: url,
                        difference: nil
                    )
                )

                _ = try Expect.notNil(
                    result.backupRecord,
                    "execution.backup.record"
                )
                try Expect.equal(
                    result.backupRecord?.originalFingerprint,
                    plan.before?.fingerprint,
                    "execution.backup.fingerprint"
                )
                try Expect.equal(
                    try workspace.read(url),
                    "after\n",
                    "execution.backup.content"
                )
            }
        }
    }

    static var storageProtocolContractFlow: TestFlow {
        TestFlow(
            "storage-protocol-contract",
            tags: ["storage", "record", "protocol"]
        ) {
            Step("mutation protocol-level id query and delete work") {
                let workspace = try TestWorkspace("storage-protocol-mutation")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let result = try writer.write(
                    "content\n",
                    options: .overwriteWithoutBackup
                )
                let record = result.mutationRecord(
                    operationKind: .write_text
                )
                let store: any WriteMutationRecordStore = WriteRecords.local.mutations(
                    directory: try workspace.directory(
                        "mutations"
                    )
                )

                let stored = try store.store(
                    record
                )

                _ = try Expect.notNil(
                    try store.stored(
                        record.id
                    ),
                    "storage.protocol.stored"
                )
                _ = try Expect.notNil(
                    try store.load(
                        record.id
                    ),
                    "storage.protocol.load-id"
                )
                try Expect.equal(
                    try store.list(
                        .target(
                            url
                        )
                    ).count,
                    1,
                    "storage.protocol.query"
                )

                try store.delete(
                    stored
                )

                try Expect.isNil(
                    try store.load(
                        record.id
                    ),
                    "storage.protocol.deleted"
                )
            }

            Step("edit protocol-level id query and delete work") {
                let workspace = try TestWorkspace("storage-protocol-edit")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "alpha\nbeta\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.preview(
                    .replaceUnique(
                        of: "beta",
                        with: "bravo"
                    )
                )
                let record = edit.record()
                let store: any WriteEditRecordStore = WriteRecords.local.edits(
                    directory: try workspace.directory(
                        "edits"
                    )
                )

                let stored = try store.store(
                    record
                )

                _ = try Expect.notNil(
                    try store.stored(
                        record.id
                    ),
                    "storage.protocol.edit.stored"
                )
                _ = try Expect.notNil(
                    try store.load(
                        record.id
                    ),
                    "storage.protocol.edit.load-id"
                )
                try Expect.equal(
                    try store.list(
                        .target(
                            url
                        )
                    ).count,
                    1,
                    "storage.protocol.edit.query"
                )

                try store.delete(
                    stored
                )

                try Expect.isNil(
                    try store.load(
                        record.id
                    ),
                    "storage.protocol.edit.deleted"
                )
            }
        }
    }

    static var rollbackPlanContractFlow: TestFlow {
        TestFlow(
            "rollback-plan-contract",
            tags: ["mutation", "rollback", "plan"]
        ) {
            Step("rollback plan previews then applies through writer") {
                let workspace = try TestWorkspace("rollback-plan-apply")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "before",
                        with: "after"
                    ),
                    options: .overwriteWithoutBackup
                )

                let record = edit.mutationRecord(
                    operationKind: .edit_operations
                )

                let plan = try writer.rollbacks.plan(
                    record,
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    plan.preview.rollbackContent,
                    "before\n",
                    "rollback.plan.content"
                )

                let result = try writer.rollbacks.apply(
                    plan
                )

                try Expect.equal(
                    try workspace.read(url),
                    "before\n",
                    "rollback.plan.applied"
                )
                try Expect.equal(
                    result.rollbackRecord.rollbackSourceID,
                    record.id,
                    "rollback.plan.source"
                )
                try Expect.equal(
                    result.rollbackRecord.rollbackStrategy,
                    .before_snapshot,
                    "rollback.plan.strategy"
                )
            }

            Step("rollback plan blocks drift") {
                let workspace = try TestWorkspace("rollback-plan-drift")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "before",
                        with: "after"
                    ),
                    options: .overwriteWithoutBackup
                )

                let record = edit.mutationRecord(
                    operationKind: .edit_operations
                )

                _ = try writer.write(
                    "drift\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "rollback.plan.drift"
                ) {
                    _ = try writer.rollbacks.plan(
                        record,
                        options: .overwriteWithoutBackup
                    )
                }

                try Expect.equal(
                    try workspace.read(url),
                    "drift\n",
                    "rollback.plan.drift-preserved"
                )
            }
        }
    }

    static var stalePlanContractFlow: TestFlow {
        TestFlow(
            "stale-plan-contract",
            tags: ["write", "plan", "stale"]
        ) {
            Step("plan blocks if file changed after planning") {
                let workspace = try TestWorkspace("stale-plan-changed")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let plan = try writer.preflight.string(
                    "after\n",
                    options: .overwriteWithoutBackup
                )

                _ = try writer.write(
                    "drift\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "stale-plan.changed"
                ) {
                    _ = try plan.execution.apply(
                        writer: writer,
                        options: .overwriteWithoutBackup,
                        conflict: SafeFileOverwriteConflict(
                            url: url,
                            difference: nil
                        )
                    )
                }

                try Expect.equal(
                    try workspace.read(url),
                    "drift\n",
                    "stale-plan.changed-preserved"
                )
            }

            Step("plan blocks if file appears after creation plan") {
                let workspace = try TestWorkspace("stale-plan-appeared")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                let plan = try writer.preflight.string(
                    "planned\n",
                    options: .overwriteWithoutBackup
                )

                _ = try writer.write(
                    "appeared\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "stale-plan.appeared"
                ) {
                    _ = try plan.execution.apply(
                        writer: writer,
                        options: .overwriteWithoutBackup,
                        conflict: SafeFileOverwriteConflict(
                            url: url,
                            difference: nil
                        )
                    )
                }

                try Expect.equal(
                    try workspace.read(url),
                    "appeared\n",
                    "stale-plan.appeared-preserved"
                )
            }

            Step("allow drift mode writes intentionally") {
                let workspace = try TestWorkspace("stale-plan-allow-drift")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                var options = SafeWriteOptions.overwriteWithoutBackup
                options.stalePlanPolicy = .allow_drift

                let plan = try writer.preflight.string(
                    "after\n",
                    options: options
                )

                _ = try writer.write(
                    "drift\n",
                    options: .overwriteWithoutBackup
                )

                _ = try plan.execution.apply(
                    writer: writer,
                    options: options,
                    conflict: SafeFileOverwriteConflict(
                        url: url,
                        difference: nil
                    )
                )

                try Expect.equal(
                    try workspace.read(url),
                    "after\n",
                    "stale-plan.allow-drift"
                )
            }
        }
    }

    static var backupRecordContractFlow: TestFlow {
        TestFlow(
            "backup-record-contract",
            tags: ["backup", "record", "restore"]
        ) {
            Step("local backup record can diff and restore") {
                let workspace = try TestWorkspace("backup-record-local")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "after\n",
                    options: .overwriting(
                        backupPolicy: .backup_directory
                    )
                )

                let backup = try Expect.notNil(
                    result.backup.record,
                    "backup-record.local.record"
                )

                let diff = try writer.backups.diff(
                    backup
                )

                try Expect.true(
                    diff.hasChanges,
                    "backup-record.local.diff"
                )

                _ = try writer.backups.restore(
                    backup,
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    try workspace.read(url),
                    "before\n",
                    "backup-record.local.restore"
                )
            }

            Step("external backup record can load through store") {
                let workspace = try TestWorkspace("backup-record-external")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let store = DirectoryBackupStore(
                    root: try workspace.directory(
                        "backups"
                    )
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    "after\n",
                    options: .overwriting(
                        backupPolicy: .external_store,
                        backupStore: store
                    )
                )

                let backup = try Expect.notNil(
                    result.backup.record,
                    "backup-record.external.record"
                )

                let data = try writer.backups.loadRequired(
                    backup,
                    store: store
                )

                try Expect.equal(
                    String(
                        data: data,
                        encoding: .utf8
                    ),
                    "before\n",
                    "backup-record.external.load"
                )
            }
        }
    }

    static var binaryRollbackContractFlow: TestFlow {
        TestFlow(
            "binary-rollback-contract",
            tags: ["write", "rollback", "binary"]
        ) {
            Step("data write rolls back from backup record") {
                let workspace = try TestWorkspace("binary-rollback")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.bin"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    Data(
                        [
                            1,
                            2,
                            3,
                        ]
                    ),
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    Data(
                        [
                            4,
                            5,
                            6,
                        ]
                    ),
                    options: .overwriting(
                        backupPolicy: .backup_directory
                    )
                )

                let record = result.mutationRecord(
                    operationKind: .write_data
                )

                _ = try writer.rollbacks.backup(
                    record,
                    options: .overwriteWithoutBackup
                )

                let data = try IntegratedReader.data(
                    at: url,
                    missingFileReturnsEmpty: false
                )

                try Expect.equal(
                    Array(data),
                    [
                        1,
                        2,
                        3,
                    ],
                    "binary-rollback.content"
                )
            }

            Step("data backup rollback blocks drift") {
                let workspace = try TestWorkspace("binary-rollback-drift")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.bin"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    Data(
                        [
                            1,
                            2,
                            3,
                        ]
                    ),
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    Data(
                        [
                            4,
                            5,
                            6,
                        ]
                    ),
                    options: .overwriting(
                        backupPolicy: .backup_directory
                    )
                )

                let record = result.mutationRecord(
                    operationKind: .write_data
                )

                _ = try writer.write(
                    Data(
                        [
                            7,
                            8,
                            9,
                        ]
                    ),
                    options: .overwriteWithoutBackup
                )

                try Expect.throwsError(
                    "binary-rollback.drift"
                ) {
                    _ = try writer.rollbacks.backup(
                        record,
                        options: .overwriteWithoutBackup
                    )
                }

                let data = try IntegratedReader.data(
                    at: url,
                    missingFileReturnsEmpty: false
                )

                try Expect.equal(
                    Array(data),
                    [
                        7,
                        8,
                        9,
                    ],
                    "binary-rollback.drift-preserved"
                )
            }
        }
    }

    static var targetPreflightContractFlow: TestFlow {
        TestFlow(
            "target-preflight-contract",
            tags: ["preflight", "backup"]
        ) {
            Step("scan is side-effect free") {
                let workspace = try TestWorkspace("target-preflight-scan")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .backup_directory
                )

                let result = try WriteTargetPreflight.scan(
                    [
                        url,
                    ],
                    options: options
                )

                try Expect.equal(
                    result.backupRecords.count,
                    0,
                    "target-preflight.scan.backups"
                )
                try Expect.equal(
                    workspace.exists(
                        url
                            .deletingLastPathComponent()
                            .appendingPathComponent(
                                options.backupDirectoryName,
                                isDirectory: true
                            )
                    ),
                    false,
                    "target-preflight.scan.no-directory"
                )
            }

            Step("prepare creates backup records") {
                let workspace = try TestWorkspace("target-preflight-prepare")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .backup_directory
                )

                let result = try WriteTargetPreflight.prepare(
                    [
                        url,
                    ],
                    options: options
                )

                try Expect.equal(
                    result.backupRecords.count,
                    1,
                    "target-preflight.prepare.backups"
                )

                let backup = try Expect.notNil(
                    result.backupRecords.first,
                    "target-preflight.prepare.first"
                )

                _ = try Expect.notNil(
                    backup.storage?.localURL,
                    "target-preflight.prepare.local-url"
                )
            }

            Step("legacy WritePreflight.run keeps prepare behavior") {
                let workspace = try TestWorkspace("target-preflight-legacy")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try WritePreflight.run(
                    [
                        url,
                    ],
                    options: .overwriting(
                        backupPolicy: .backup_directory
                    )
                )

                try Expect.equal(
                    result.backupRecords.count,
                    1,
                    "target-preflight.legacy.backups"
                )
            }
        }
    }

    static var payloadPolicyContractFlow: TestFlow {
        TestFlow(
            "payload-policy-contract",
            tags: ["storage", "payload"]
        ) {
            Step("external content stores payload manifest and strips inline content") {
                let workspace = try TestWorkspace("payload-policy-external")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "before",
                        with: "after"
                    ),
                    options: .overwriteWithoutBackup
                )

                let record = edit.mutationRecord(
                    operationKind: .edit_operations,
                    storeContent: true
                )

                let store = WriteRecords.local.mutations(
                    directory: try workspace.directory(
                        "mutations"
                    )
                )

                let stored = try store.store(
                    record,
                    payloadPolicy: .external_content
                )

                let loaded = try Expect.notNil(
                    try store.load(
                        stored
                    ),
                    "payload-policy.external.loaded"
                )

                try Expect.isNil(
                    loaded.before?.content,
                    "payload-policy.external.before-stripped"
                )
                try Expect.isNil(
                    loaded.after?.content,
                    "payload-policy.external.after-stripped"
                )
                _ = try Expect.notNil(
                    loaded.metadata[
                        WriteMutationPayloadMetadataKey.payload_manifest
                    ],
                    "payload-policy.external.manifest"
                )
                _ = try Expect.notNil(
                    loaded.metadata[
                        WriteMutationPayloadMetadataKey.payload_before
                    ],
                    "payload-policy.external.before-ref"
                )
                _ = try Expect.notNil(
                    loaded.metadata[
                        WriteMutationPayloadMetadataKey.payload_after
                    ],
                    "payload-policy.external.after-ref"
                )
            }

            Step("metadata only stores no inline content and no payload refs") {
                let workspace = try TestWorkspace("payload-policy-metadata")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "before",
                        with: "after"
                    ),
                    options: .overwriteWithoutBackup
                )

                let record = edit.mutationRecord(
                    operationKind: .edit_operations,
                    storeContent: true
                )

                let store = WriteRecords.local.mutations(
                    directory: try workspace.directory(
                        "mutations"
                    )
                )

                let stored = try store.store(
                    record,
                    payloadPolicy: .metadata_only
                )

                let loaded = try Expect.notNil(
                    try store.load(
                        stored
                    ),
                    "payload-policy.metadata.loaded"
                )

                try Expect.isNil(
                    loaded.before?.content,
                    "payload-policy.metadata.before-stripped"
                )
                try Expect.isNil(
                    loaded.after?.content,
                    "payload-policy.metadata.after-stripped"
                )
                try Expect.equal(
                    loaded.metadata[
                        WriteMutationPayloadMetadataKey.payload_policy
                    ],
                    WriteMutationPayloadPolicy.metadata_only.rawValue,
                    "payload-policy.metadata.policy"
                )
                try Expect.isNil(
                    loaded.metadata[
                        WriteMutationPayloadMetadataKey.payload_manifest
                    ],
                    "payload-policy.metadata.no-manifest"
                )
            }
        }
    }

    static var rollbackSurfaceContractFlow: TestFlow {
        TestFlow(
            "rollback-surface-contract",
            tags: ["mutation", "rollback", "surface"]
        ) {
            Step("text rollback surface exposes text strategies") {
                let workspace = try TestWorkspace("rollback-surface-text")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let edit = try writer.editor.edit(
                    .replaceUnique(
                        of: "before",
                        with: "after"
                    ),
                    options: .overwriteWithoutBackup
                )

                let record = edit.mutationRecord(
                    operationKind: .edit_operations,
                    storeContent: true
                )

                try Expect.equal(
                    record.surface.rollback.textAvailable,
                    true,
                    "rollback-surface.text.available"
                )
                try Expect.equal(
                    record.surface.rollback.backupAvailable,
                    false,
                    "rollback-surface.text.no-backup"
                )
                try Expect.true(
                    record.surface.rollback.strategies.contains(
                        .before_snapshot
                    ),
                    "rollback-surface.text.strategy"
                )
            }

            Step("binary rollback surface exposes backup strategy") {
                let workspace = try TestWorkspace("rollback-surface-binary")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.bin"
                )
                let writer = StandardWriter(
                    url
                )

                _ = try writer.write(
                    Data(
                        [
                            1,
                            2,
                            3,
                        ]
                    ),
                    options: .overwriteWithoutBackup
                )

                let result = try writer.write(
                    Data(
                        [
                            4,
                            5,
                            6,
                        ]
                    ),
                    options: .overwriting(
                        backupPolicy: .backup_directory
                    )
                )

                let record = result.mutationRecord(
                    operationKind: .write_data
                )

                try Expect.equal(
                    record.surface.rollback.textAvailable,
                    false,
                    "rollback-surface.binary.no-text"
                )
                try Expect.equal(
                    record.surface.rollback.backupAvailable,
                    true,
                    "rollback-surface.binary.backup"
                )
                try Expect.true(
                    record.surface.rollback.strategies.contains(
                        .backup_record
                    ),
                    "rollback-surface.binary.strategy"
                )
                try Expect.equal(
                    record.surface.rollback.available,
                    true,
                    "rollback-surface.binary.available"
                )
            }
        }
    }
}
