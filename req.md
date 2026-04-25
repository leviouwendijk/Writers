
---
---

PREVIOUS CONVERSATION HISTORY CONTEXT:

---

USER:
    > ~/myworkdir/programming/libraries/swift/Writers $ swift run wtest                                        @levi-m2 [15:04:57]
    Building for debugging...
    [1/1] Write swift-version--1AB21518FC5DEDBE.txt
    Build of product 'wtest' complete! (0.10s)
    Writers flow tests
    ====================

    pass  write-mutation             3ms

    pass  backup-policy              3ms

    pass  backup-prune               1ms

    pass  external-backup-store      2ms

    pass  preflight                  2ms

    pass  write-contract             3ms

    pass  overwrite-conflict         1ms

    pass  edit-preview-and-rollback  2ms

    pass  edit-record-store          2ms

    pass  record-storage             5ms

    pass  storage-location-contract  1ms

    pass  mutation-surface-contract  0ms

    pass  edit-merge                 2ms

    pass  mutation-rollback          6ms

    pass  mutation-snapshot          2ms

    ====================
    pass 15/15 passed
    > ~/myworkdir/programming/libraries/swift/Writers $                                                        @levi-m2 [15:04:59]


    assess if we are meeting our initial intended plans:

    Yes — this should become a first-class system mechanic, not a side effect of `write_file`.

    The clean split is:

    ```text
    Writers owns:
        safe mutation mechanics
        backup creation
        diff/change detection
        rollback metadata
        snapshot/fingerprint logic

    Agentic owns:
        mutation policy
        session ledger
        artifact emission
        approval/preflight UX
        cleanup/retention policy
    ```

    ## Current state

    Your suspicion is right: the local backup directories happen because `FileEditor` defaults writes and edits to `SafeWriteOptions.overwrite`, and Writers’ overwrite mode defaults to backup-on-overwrite with backup directories enabled. `WriteOptions` has `makeBackupOnOverride`, `createBackupDirectory`, `backupDirectoryName`, `backupSetPrefix`, and `maxBackupSets`; by default backup directories are enabled and `maxBackupSets` is nil unless overridden.   Agentic’s `FileEditor.write` currently calls `StandardWriter(...).editor.edit(.replaceEntireFile(...), options: .overwrite)` by default. 

    Writers already has more rollback-relevant data than a simple `.bak` file. `StandardEditResult` stores original content, edited content, a structured difference, changes, and the underlying write result.  It also exposes changed line ranges and rollback operations derived from those changes.  There is also a snapshot/set model that checks whether the current content still matches the edited fingerprint before rollback, which is exactly the kind of deterministic guard you want. 

    So I would not solve this by ripping backups out. I’d strengthen the model.

    ## The core design

    Make every file mutation produce a **MutationRecord**.

    That record should be append-only session data, stored under AgentHome by default, not beside the target file. The physical backup is optional payload storage, not the primary source of truth.

    ```text
    AgentMutationRecord
        id
        sessionID
        toolCallID
        createdAt

        rootID
        scopedPath
        absolutePathFingerprint maybe, not always raw path in public export

        operationKind
            write_entire_file
            edit_operations
            append
            future_patch

        risk
        approvalID?
        preflightID?

        before
            fingerprint
            byteCount
            lineCount
            optionalContentStorageRef

        after
            fingerprint
            byteCount
            lineCount
            optionalContentStorageRef

        difference
            insertions
            deletions
            changeCount
            changedLineRanges
            diffArtifactID?

        rollback
            rollbackOperations
            canRollbackOnlyIfCurrentFingerprint == after.fingerprint
            backupRef?
            rollbackStatus

        writer
            writeOptionsSnapshot
            backupURL?
            backupPolicy
    ```

    That gives you inspection, rollback, and artifacts without requiring visible sibling backup folders.

    ## Backup policy should be explicit

    I would introduce a small Agentic-level enum that maps to Writers options:

    ```text
    AgentFileBackupPolicy
        none
        inlineSibling
        localBackupDirectory
        sessionMutationStore
        bothSessionAndLocal
    ```

    Recommended defaults:

    ```text
    normal Agentic write_file:
        sessionMutationStore

    manual/local power-user mode:
        localBackupDirectory(maxBackupSets: 10)

    paranoid/release-critical mode:
        bothSessionAndLocal

    scratch/generated artifact mode:
        none
    ```

    In other words: **Agentic default should not create `safe-file-backups/` beside project files**. It should store mutation payloads in the session/home mutation store. Writers can still support local backup directories, but Agentic should opt into them intentionally.

    Writers already has the knobs for this: `makeBackupOnOverride`, `createBackupDirectory`, `backupDirectoryName`, `backupSetPrefix`, and `maxBackupSets`.  The `.overwrite` convenience currently sets overwrite, whitespace blank handling, and `maxBackupSets: 10`, but still participates in the backup behavior. 

    ## Artifacts: yes, but not every overwrite is “a new file artifact”

    I would separate **workspace mutation** from **artifact emission**.

    A file overwritten in place is not automatically an “artifact” in the same sense as a generated report, context pack, or exported diff. But the mutation should be able to emit artifacts:

    ```text
    Always store:
        AgentMutationRecord

    Sometimes emit:
        diff artifact
        before snapshot artifact
        after snapshot artifact
        rollback bundle artifact
        human-readable edit report artifact
    ```

    Agentic already has artifact kinds for `diff`, `report`, `context_pack`, etc., and `diff` maps to `.diff` / `text/x-diff`.   `AgentArtifact` already has session ID, kind, filename, byte count, created date, and metadata, while `AgentArtifactDraft` can carry content plus metadata.  

    So the rule should be:

    ```text
    MutationRecord:
        machine audit + rollback source of truth

    Artifact:
        exported/viewable derived material
    ```

    That keeps artifacts useful instead of turning them into a noisy mirror of every file mutation.

    ## Strengthen Writers first

    I’d add a real backup/mutation model to Writers before overbuilding Agentic wrappers.

    ### Writers additions

    ```text
    WriteBackupPolicy
        disabled
        siblingFile
        backupDirectory
        externalStore

    WriteBackupRecord
        id
        target
        backupURL?
        createdAt
        originalFingerprint
        byteCount
        policy

    WriteMutationSnapshot
        content
        fingerprint
        lineCount
        byteCount

    WriteMutationRecord
        target
        options
        backupRecord?
        editResult
    ```

    The key is `externalStore`. Writers should not know about AgentHome, but it can support a protocol:

    ```text
    WriteBackupStore
        storeBackup(...)
        loadBackup(...)
    ```

    Then Agentic implements that protocol using its session mutation store.

    That gives you:

    ```text
    Writers:
        can write backup somewhere other than beside target

    Agentic:
        decides where that somewhere is
    ```

    ## Agentic mutation store

    Add this under AgentHome:

    ```text
    sessions/<session-id>/mutations/
        mutations.jsonl
        content/
            <mutation-id>/
                before.txt
                after.txt
                diff.diff
                rollback.json
    ```

    Or, if you want global indexing later:

    ```text
    mutations/
        <session-id>.jsonl
        content/<session-id>/<mutation-id>/
    ```

    I’d start session-local because it matches tool runs and makes cleanup easier.

    Retention:

    ```text
    keep mutation ledger forever unless session deleted
    keep full before/after content for N latest or until size cap
    keep diffs longer than full snapshots
    allow prune command:
        keep latest N
        keep last X days
        drop before/after payloads but retain metadata/diff
    ```

    ## Rollback model

    Rollback should be deterministic and guarded:

    ```text
    rollback_file_mutation(mutationID)
        load mutation record
        resolve same rootID/path
        read current content
        verify current fingerprint == mutation.after.fingerprint
        apply rollbackOperations or restore before snapshot
        write through Writers as a new mutation
        record rollbackOf: mutationID
    ```

    Never silently rollback if the file has drifted. If the fingerprint does not match, return:

    ```text
    rollback blocked:
        current file no longer matches post-mutation snapshot
        provide diff current vs expected-after
        require merge/manual review
    ```

    This is better than “restore backup over current file,” because it does not crush later work.

    ## Preflight delta tracking

    For preflight, do not wait until execution to know what will happen. Agentic already has preview calls: `FileEditor.previewWrite` previews `.replaceEntireFile(with:)` through `StandardWriter(...).editor.preview`, and preview edit variants exist too.   Use that to build:

    ```text
    ToolPreflight.diffPreview
    ToolPreflight.estimatedWriteCount
    ToolPreflight.targetPaths
    ToolPreflight.sideEffects
    ToolPreflight.backupPolicy
    ```

    Then the approval UI can show the diff before the tool runs. You already have the interface side for this: `TerminalApprovalPicker` has a `showDiff` path, and renders `ToolPreflightDiffPreview` with `DifferenceRenderer.Terminal.render` when a layout exists.  

    ## Recommended staged plan

    ### Phase 1 — stop local clutter by default

    Change Agentic file tools to construct an explicit write options policy instead of using `.overwrite` directly.

    Default:

    ```text
    existingFilePolicy: .overwrite
    makeBackupOnOverride: true
    createBackupDirectory: false initially OR external store once available
    maxBackupSets: nil irrelevant if no local directory
    ```

    Actually, after the external store exists, default becomes:

    ```text
    makeBackupOnOverride: true
    backupPolicy: .sessionMutationStore
    ```

    Until then, you can set `createBackupDirectory: false` for generated/scratch files and keep `.overwrite` for “safe local test mode.”

    ### Phase 2 — add AgentMutationRecord

    Capture every successful `write_file` / `edit_file` result:

    ```text
    StandardEditResult
        -> AgentMutationRecord
        -> optional diff artifact
        -> transcript event
    ```

    Do not duplicate all Writers structures. Store references and compact summaries, plus enough snapshot/fingerprint data for rollback.

    ### Phase 3 — Writers backup API hardening

    Add named backup policies and a store protocol in Writers. Keep the existing options as compatibility sugar, but make the new API clearer than raw booleans.

    ### Phase 4 — rollback tool

    Add:

    ```text
    list_file_mutations
    inspect_file_mutation
    rollback_file_mutation
    prune_file_mutation_payloads
    ```

    `rollback_file_mutation` should be `boundedMutate` and require approval unless the session mode explicitly allows bounded mutation.

    ### Phase 5 — cleanup tools

    Add cleanup at two levels:

    ```text
    Writers local cleanup:
        prune safe-file-backups directories
        keep N latest sets
        delete older than date

    Agentic cleanup:
        prune mutation payloads
        keep mutation metadata
        prune diff artifacts by policy
    ```

    ## My recommendation

    Make **session mutation storage the Agentic default**, and keep Writers’ local backup directories as an opt-in local safety mode.

    That gets you the best of both worlds:

    ```text
    No clutter:
        no constant safe-file-backups beside project files

    Good inspection:
        every mutation is visible in session history

    Good rollback:
        fingerprint-guarded rollback, not blind restore

    Good artifacts:
        diffs/reports are emitted when useful, not for every internal step

    Good library design:
        Writers becomes stronger and deterministic
        Agentic remains orchestration/policy/storage
    ```

    The most important next implementation move is: **create `AgentMutationRecord` and route `WriteFileTool` / `EditFileTool` through a mutation recorder**, while leaving the deeper Writers backup-store protocol for the next pass.

---


SYSTEM:

    Yes. We’re meeting the **Writers half** of the plan very well now. We are **not yet meeting the Agentic half** except for having the supporting artifact/prepared-intent infrastructure already present.

    ## Assessment

    ### Writers owns safe mutation mechanics: yes

    This is basically achieved.

    `WriteMutationRecord` now has the core fields we wanted: id, target, createdAt, operation kind, before/after snapshots, difference summary, backup record, write result, rollback operations, rollback guard, and metadata.  The conversion helpers from `WriteResult`, `StandardEditResult`, and `StandardEditRecord` also now produce mutation records with snapshots and rollback guards. 

    The classification split is also in place: resource-level `creation/update/deletion/unknown` and delta-level `addition/deletion/replacement/unchanged/unknown` are computed from snapshots and diffs. 

    ### Writers owns rollback metadata and guarded rollback: yes

    This is achieved.

    Rollback is fingerprint-guarded through `WriteRollbackGuard`, and rollback can use either before-snapshot content or rollback operations. The record model stores the guard, and the rollback path blocks if current content no longer matches the required fingerprint.  

    The typed metadata wrapper is also now aligned with the plan: `rollbackOf`, `rollbackStrategy`, `resource`, and `delta` are typed wrappers over raw string metadata. 

    ### Writers owns storage seams: mostly yes

    This is now substantially achieved.

    You have `WriteRecords.local.mutations(directory:)` and `WriteRecords.local.edits(directory:)`, plus store wrappers with `save`, `load`, id-based load, query filtering, and delete.  Local mutation storage writes JSON records and returns a typed stored-record descriptor with `.local(url)` storage. 

    This means Writers no longer only has “a backup file somewhere”; it has a real mutation-record storage model. That is exactly the right precursor for Agentic’s session mutation ledger.

    ### Writers owns preflight/data review: partially yes

    This is in place as a review seam, but not yet fully unified with write execution.

    `WritePlan` carries target, incoming data, before/after snapshots, collision, resource/delta classification, backup policy, and `canProceed`. It can also emit a `WriteMutationRecord`.  The nested `writer.preflight.string(...)` / `.data(...)` API is also now present. 

    What is still missing: `StandardWriter.write(...)` is not yet implemented *through* `WritePlan.execute()` or an equivalent shared execution object. So preflight prediction and actual write are covered by tests now, but still structurally separate. That is acceptable for this stage, but it is the next place drift can creep in.

    ### Agentic owns mutation policy/session ledger/artifact emission: not yet

    This is the main remaining gap.

    Agentic has the infrastructure pieces: artifact kinds include `diff`, `report`, etc.  There is an `AgentArtifactStore` protocol for emitting/listing/loading artifacts.  The file-backed artifact store already writes content and metadata under an artifact directory. 

    But `FileEditor` still directly calls `StandardWriter(...).editor.edit(...)` and defaults to `SafeWriteOptions.overwrite`; it returns `StandardEditResult`, not an Agentic mutation record or ledger entry.  The same is true for raw-path writes and edit operations: options default to `.overwrite`, and the calls are direct writer/editor calls.  

    So: Writers is ready. Agentic is still not yet consuming the new mechanics.

    ## Where we stand against the original split

    ```text
    Writers owns:
        safe mutation mechanics             yes
        backup creation                     yes
        diff/change detection               yes
        rollback metadata                   yes
        snapshot/fingerprint logic          yes
        storage seams                       yes, now good
        preflight review object             yes, but not execution-unified yet

    Agentic owns:
        mutation policy                     not yet
        session ledger                      not yet
        artifact emission                   infrastructure yes, mutation integration no
        approval/preflight UX               infrastructure yes, write integration not yet
        cleanup/retention policy            not yet
    ```

    ## Verdict

    We have completed the **Writers foundation** for the original design. The green `15/15` confirms this pass is stable enough to start Agentic integration.

    The next implementation should be in **Agentic**, not Writers:

    ```text
    1. Add AgentMutationRecord / AgentMutationStore.
    2. Add FileAgentMutationStore under session-local AgentHome storage.
    3. Add AgentFileBackupStore: WriteBackupStore.
    4. Add AgentFileMutationPolicy.
    5. Change FileEditor defaults away from raw .overwrite.
    6. Route write/edit through a mutation recorder.
    7. Optionally emit diff artifacts from successful mutations.
    ```

    The key next goal is: `FileEditor.write` should no longer merely return `StandardEditResult`; it should produce or record an Agentic mutation entry backed by Writers’ `WriteMutationRecord`.


---

USER:

    no, let's finalize writers in full before moving on. i want that execution unification etc., andything that is missing in storage or whaevet. first FINISH Strong on writers. create the plan

---

SYSTEM:

    Agreed. Writers should be **finished as a deterministic mutation engine** before Agentic starts depending on it.

    Current state: `WritePlan` exists and already carries target, incoming content, before/after snapshots, collision, resource/delta kinds, backup policy, and `canProceed` . But `StandardWriter.write(...)` still routes through private `writePrepared(...)`, which separately reads existing data, checks blank/collision status, creates backups, writes bytes, and builds `WriteResult` . That is the final structural duplication to remove. Storage is close too, but the protocols are still minimal (`store/load/list`) while the wrapper carries the richer id/query/delete API .

    ## Goal

    Finish Writers as:

    ```text
    WritePlan
        single source of truth for preflight, collision, snapshots, classifications, backup decision

    WriteExecution
        executes a WritePlan exactly once
        creates backup once
        writes bytes once
        returns WriteResult
        can emit WriteMutationRecord

    WriteStorage
        typed storage descriptors
        local + external-safe
        id/query/delete in contract, not only wrapper sugar

    WriteRollback
        remains fingerprint-guarded
        returns typed rollback mutation metadata
    ```

    ## Phase 1 — make `WritePlan` execution-grade

    Right now `WritePlan` is review-grade. Upgrade it so execution does not need to rediscover the same facts.

    Add fields:

    ```swift
    public let options: SafeWriteOptions
    public let existingData: Data?
    public let existingIsBlank: Bool
    public let overwriteAction: WriteOverwriteAction
    ```

    Add primitive:

    ```swift
    public enum WriteOverwriteAction: String, Codable, Sendable, Hashable, CaseIterable {
        case create
        case overwrite_blank
        case overwrite_nonblank
        case abort_collision
        case unchanged
    }
    ```

    Then `WritePlan.requireClean()` becomes based on `overwriteAction`, not just `canProceed`.

    Why: `writePrepared` currently determines collision and backup by re-reading file state. That means preflight and write can drift. A real plan should carry the exact decision that execution follows.

    ## Phase 2 — introduce `WriteExecution`

    Add:

    ```swift
    public struct WriteExecution: Sendable {
        public let plan: WritePlan

        public func apply(
            conflict: @autoclosure () -> SafeFileOverwriteConflict
        ) throws -> WriteResult
    }
    ```

    This becomes the one code path that:

    ```text
    1. ensures parent directory
    2. checks plan.canProceed
    3. creates backup only if plan says overwrite_nonblank and policy requires backup
    4. writes data
    5. returns WriteResult using plan.before / plan.after
    ```

    The old `StandardWriter.write(...)` methods should become:

    ```swift
    let plan = try writePlan(...)
    return try plan.execution.apply(conflict: overwriteConflict(...))
    ```

    So public behavior stays stable, but the internal source of truth becomes `WritePlan`.

    ## Phase 3 — remove duplicate backup creation paths

    After Phase 2, only one internal function should create backups.

    Current duplicate-ish sources:

    ```text
    StandardWriter.writePrepared -> makeBackupRecord
    WritePreflight.run -> makeBackup
    ```

    Keep `WritePreflight.run` as a compatibility API, but make it build plans and gather their preview backup requirements.

    New shape:

    ```swift
    WritePreflight.run(targets, options)
        -> targets.map { StandardWriter($0).writePlan(empty/incoming?)? }
    ```

    But because current `preflightSafeWrite(_ targets:)` does not know incoming content, keep it as a **target-safety preflight**, not a write-plan preflight. Rename internally:

    ```swift
    WriteTargetPreflight
    ```

    Then maintain public compatibility:

    ```swift
    preflightSafeWrite(...) -> WriteTargetPreflight.run(...).requireClean()
    ```

    This separates two concepts cleanly:

    ```text
    WritePlan            preflight for a concrete incoming write
    WriteTargetPreflight safety scan for target paths before an external write operation
    ```

    ## Phase 4 — formalize backup loading/storage around `WriteStorageLocation`

    Backup records now have typed storage in the latest pass, while `backupURL` is only a compatibility bridge. Keep that. The plan should finish this by making backup loading not assume local unless the store is local.

    Add wrapper:

    ```swift
    public struct WriteBackupRecordStorageAPI {
        public let record: WriteBackupRecord

        public var localURL: URL? { record.storage?.localURL }
        public func requireLocalURL() throws -> URL
    }
    ```

    Call site:

    ```swift
    backup.storage.localURL
    ```

    But there is a naming collision if the field is already called `storage`, so use:

    ```swift
    backup.location.localURL
    ```

    or rename field later only with deprecation. For now:

    ```swift
    backup.stored.localURL
    backup.stored.requireLocalURL()
    ```

    Also add:

    ```swift
    public protocol WriteBackupRecordStore: Sendable {
        func store(_ request: WriteBackupRequest) throws -> WriteBackupRecord
        func load(_ record: WriteBackupRecord) throws -> Data?
        func delete(_ record: WriteBackupRecord) throws
    }
    ```

    Keep `WriteBackupStore` as the compatibility protocol for now.

    ## Phase 5 — make record-store richer at protocol level

    Right now the protocol only promises `store`, `load(stored:)`, and `list()` . The wrapper adds nicer behavior, but Agentic should not rely on wrapper-only semantics when custom stores arrive.

    Promote these to protocol requirements with extension defaults where possible:

    ```swift
    func stored(_ id: UUID) throws -> WriteStoredRecord?
    func load(_ id: UUID) throws -> WriteMutationRecord?
    func list(_ query: WriteRecordQuery) throws -> [WriteStoredRecord]
    func delete(_ stored: WriteStoredRecord) throws
    ```

    For source compatibility, do it like:

    ```swift
    public extension WriteMutationRecordStore {
        func stored(_ id: UUID) throws -> WriteStoredRecord? { ... }
        func load(_ id: UUID) throws -> WriteMutationRecord? { ... }
        func list(_ query: WriteRecordQuery) throws -> [WriteStoredRecord] { ... }
        func delete(_ stored: WriteStoredRecord) throws { ... }
    }
    ```

    Then the wrapper can forward to protocol-level methods instead of owning the behavior.

    ## Phase 6 — storage manifests and payload layout

    Local mutation records currently store a single JSON file per mutation. That is good, but not enough for large payloads later. The mutation snapshot has optional inline content, and `StandardEditResult.mutationRecord(storeContent:)` already supports content omission .

    Add a typed payload manifest:

    ```swift
    WriteMutationPayloadPolicy
        inline
        external_content
        metadata_only

    WriteMutationPayloadRecord
        mutationID
        before: WriteStorageLocation?
        after: WriteStorageLocation?
        diff: WriteStorageLocation?
        rollback: WriteStorageLocation?
    ```

    Do not force external payloads yet. Add the model + local helper only:

    ```swift
    StandardMutationRecordStore.Payloads
        storeBefore(...)
        storeAfter(...)
        storeDiff(...)
    ```

    This lets Writers later hand Agentic clean content refs instead of giant JSON records.

    ## Phase 7 — execution result wrappers

    `WriteResult` still has `backupURL` directly for compatibility, plus `backupRecord`. It also has snapshots and byte counts. The plan should add wrapper accessors instead of deleting fields.

    Add:

    ```swift
    result.summary.resource
    result.summary.delta
    result.summary.backup
    result.summary.mutationRecord(operationKind:)
    result.backup.record
    result.backup.localURL
    ```

    This keeps flat fields usable but gives Agentic/Writers internal code the nested style.

    ## Phase 8 — rollback polish

    Rollback is functionally good: rollback validates target and fingerprint, then writes rollback content through `write(...)`, and records rollback metadata with `rollback_of`, `rollback_strategy`, `resource_change`, and `delta_kind` .

    Finish it by adding:

    ```swift
    writer.rollbacks.plan(record)
    writer.rollbacks.preview(record)
    writer.rollbacks.apply(record)

    WriteRollbackPlan
        record
        preview
        options
        metadata
    ```

    This aligns rollback with the new write execution model: plan first, execute second.

    ## Phase 9 — tests to lock it down

    Add or revise flows:

    ```text
    write-execution-contract
        writePlan and write result share before/after fingerprints
        write through plan creates the same result as writer.write
        backup is created exactly once
        abort plan does not write or backup

    target-preflight-contract
        target preflight can create backup without mutating target
        target preflight external store requires store
        target preflight result distinguishes target scan from write plan

    storage-protocol-contract
        protocol-level load(id), stored(id), list(query), delete work
        external storage location never pretends to be local
        delete on missing local record is idempotent

    backup-storage-contract
        backup record local location loads through wrapper
        external backup store round trips bytes
        backupURL bridge still works but only in compatibility test

    rollback-plan-contract
        rollback plan blocks drift
        rollback plan executes through unified writer execution
        rollback record metadata is typed and surfaced
    ```

    Your current `15/15` is a good base, but this new set should specifically test the **single source of truth** guarantee.

    ## Phase 10 — cleanup/deprecation pass

    Only after green tests:

    ```text
    deprecate direct backupURL reads in WriteResult if possible
    deprecate any old makeSimpleLineDiff/makeStructuredLineDiff surfaces if still present
    remove private duplicate helpers that become unused after WriteExecution
    rename internal WritePreflight implementation to WriteTargetPreflight if public name must stay
    ```

    ## Implementation order

    Do it in this exact order:

    ```text
    1. Add WriteOverwriteAction and upgrade WritePlan.
    2. Add WriteExecution and route StandardWriter.write through it.
    3. Keep writePrepared temporarily as deprecated/private bridge, then delete once tests pass.
    4. Split concrete write planning from target preflight.
    5. Promote record id/query/delete to protocol extensions.
    6. Add backup record wrapper APIs.
    7. Add mutation payload manifest models.
    8. Add rollback plan API.
    9. Add execution/storage/rollback contract flows.
    10. Cleanup deprecated/internal duplicate paths.
    ```

    The first real drop-in pass should be **steps 1–3 + execution contract tests**. That is the critical core. Once that is green, the storage and rollback refinements become much safer.

---
---

Proceed with the plan of finishing off Writers lib. Give me the relevant drop ins.
