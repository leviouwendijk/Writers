import Foundation
import Position

/// Conflict footprints are expressed in the original file revision's coordinates.
/// Whole-resource reservations also cover descendant resources (directory mutations).
public enum StandardMutationFootprint: Sendable {
    case resource(URL)
    case lines(URL, [LineRange])
    case insertions(URL, [Int])

    public var file: URL {
        switch self {
        case .resource(let file), .lines(let file, _), .insertions(let file, _):
            return file
        }
    }

    public func overlaps(_ other: Self) -> Bool {
        let left = file.standardizedFileURL.resolvingSymlinksInPath().path
        let right = other.file.standardizedFileURL.resolvingSymlinksInPath().path
        if case .resource = self {
            return left == right || right.hasPrefix(left + "/") || left.hasPrefix(right + "/")
        }
        if case .resource = other {
            return left == right || right.hasPrefix(left + "/") || left.hasPrefix(right + "/")
        }
        guard left == right else { return false }
        switch (self, other) {
        case (.lines(_, let a), .lines(_, let b)):
            return a.contains { x in b.contains { y in x.start <= y.end && y.start <= x.end } }
        case (.insertions(_, let a), .insertions(_, let b)):
            return a.contains { b.contains($0) }
        case (.lines(_, let spans), .insertions(_, let at)),
             (.insertions(_, let at), .lines(_, let spans)):
            return at.contains { point in spans.contains { $0.start <= point && point <= $0.end } }
        default:
            return false
        }
    }
}

public enum StandardMutationCoordinationError: Error, Sendable {
    case unknown_participant(UUID)
    case closed_participant(UUID)
    case unknown_submission(UUID)
    case submission_not_owned(UUID)
    case submission_not_pending(UUID)
    case conflict(file: URL, blocking_submission: UUID)
    case unsupported_merge(URL)
    case incompatible_edit_options(URL)
    case overlapping_submission_footprints(URL)
    case publication_attribution_missing(URL)
    case unknown_publication(UUID)
    case publication_already_rolled_back(UUID)
    case publication_not_rollbackable(UUID)
    case staged_visibility_unsupported(URL)
    case requires_recovery
}

public enum StandardMutationSubmissionState: Sendable {
    case pending
    case withdrawn
    case committed(UUID)
    case rolled_back
    case failed
}

public struct StandardMutationSubmission: Sendable, Identifiable {
    public let id: UUID
    public let participant_id: UUID
    public let plan: StandardMutationPlan
    public let footprints: [StandardMutationFootprint]
    public let state: StandardMutationSubmissionState

    fileprivate func with_state(_ state: StandardMutationSubmissionState) -> Self {
        .init(id: id, participant_id: participant_id, plan: plan, footprints: footprints, state: state)
    }
}

/// A submission capability; only the coordinator owner may publish mutations.
public struct StandardMutationParticipant: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    private let coordinator: StandardMutationCoordinator

    fileprivate init(id: UUID, name: String, coordinator: StandardMutationCoordinator) {
        self.id = id
        self.name = name
        self.coordinator = coordinator
    }

    @discardableResult
    public func submit(
        _ entries: [StandardMutationEntry],
        metadata: [String: String] = [:]
    ) async throws -> StandardMutationSubmission {
        try await coordinator.submit(participant_id: id, entries: entries, metadata: metadata)
    }

    @discardableResult
    public func submit(
        _ entry: StandardMutationEntry,
        metadata: [String: String] = [:]
    ) async throws -> StandardMutationSubmission {
        try await submit([entry], metadata: metadata)
    }

    /// Submit an already prepared mutation plan unchanged. Use this when a
    /// downstream caller has shown its preview for approval: never replan a
    /// different mutation as part of accepting that approval.
    /// Publication still enforces the plan's current-state requirements.
    @discardableResult
    public func submit(_ plan: StandardMutationPlan) async throws -> StandardMutationSubmission {
        try await coordinator.submit(participant_id: id, plan: plan)
    }

    public func withdraw(_ submission_id: UUID) async throws {
        try await coordinator.withdraw(participant_id: id, submission_id: submission_id)
    }

    public func close() async throws {
        try await coordinator.close(participant_id: id)
    }
}

/// Attribution for one source operation. Several disjoint source operations may
/// map to the same published entry and physical mutation record.
public struct StandardMutationEntryContribution: Sendable, Codable, Hashable {
    public let source_entry_id: UUID
    public let published_entry_id: UUID
    public let mutation_record_id: UUID?
    public let was_applied: Bool

    public init(
        source_entry_id: UUID,
        published_entry_id: UUID,
        mutation_record_id: UUID?,
        was_applied: Bool
    ) {
        self.source_entry_id = source_entry_id
        self.published_entry_id = published_entry_id
        self.mutation_record_id = mutation_record_id
        self.was_applied = was_applied
    }
}

/// Preserves the identity and metadata of a participant's original, individually
/// validated plan even when multiple submissions share one physical write.
public struct StandardMutationContribution: Sendable, Codable, Hashable {
    public let submission_id: UUID
    public let participant_id: UUID
    public let source_plan_id: UUID
    public let source_plan_metadata: [String: String]
    public let entries: [StandardMutationEntryContribution]

    public init(
        submission_id: UUID,
        participant_id: UUID,
        source_plan_id: UUID,
        source_plan_metadata: [String: String],
        entries: [StandardMutationEntryContribution]
    ) {
        self.submission_id = submission_id
        self.participant_id = participant_id
        self.source_plan_id = source_plan_id
        self.source_plan_metadata = source_plan_metadata
        self.entries = entries
    }
}

/// Publication-wide result plus durable attribution of the original plans.
/// was_applied means the physical entry was attempted successfully, NOT that it
/// survived an automatic rollback. Check result.status and automaticRollback.
public struct StandardMutationPublication: Sendable, Codable, Hashable {
    public let result: StandardMutationResult
    public let submission_ids: [UUID]
    public let contributions: [StandardMutationContribution]

    public init(
        result: StandardMutationResult,
        submission_ids: [UUID],
        contributions: [StandardMutationContribution]
    ) {
        self.result = result
        self.submission_ids = submission_ids
        self.contributions = contributions
    }
}

/// A reusable process-owned coordinator over the canonical mutation planner/applier.
/// It never publishes through a separate edit writer. Staged edits share base coordinates;
/// publication combines disjoint edits to one file into one snapshot-mode mutation entry.
public actor StandardMutationCoordinator {
    private var participants: [UUID: Bool] = [:]
    private var submissions: [UUID: StandardMutationSubmission] = [:]
    private var order: [UUID] = []
    private var publications: [UUID: StandardMutationPublication] = [:]
    private var rolled_back_publications: Set<UUID> = []
    private var rollback_results: [StandardMutationRollbackResult] = []
    private var blocked = false

    public init() {}

    public func participant(name: String) -> StandardMutationParticipant {
        let id = UUID()
        participants[id] = true
        return .init(id: id, name: name, coordinator: self)
    }

    public func journal() -> [StandardMutationSubmission] {
        order.compactMap { submissions[$0] }
    }

    /// Owner-side committed publications and rollback outcomes are durable values.
    /// If recovery is required, reconstruct the coordinator only after the owner
    /// has reconciled the filesystem; do not silently unlock uncertain effects.
    public func publication(_ id: UUID) -> StandardMutationPublication? {
        publications[id]
    }

    public func rollback_journal() -> [StandardMutationRollbackResult] {
        rollback_results
    }

    public func requires_recovery() -> Bool {
        blocked
    }

    /// Explicit lifecycle observable by the host; does not expose capabilities
    /// for another participant or permit mutation publication.
    public func pending_submission_ids() -> [UUID] {
        order.filter { id in
            guard let submission = submissions[id] else { return false }
            if case .pending = submission.state { return true }
            return false
        }
    }

    /// Cancel a pending publication round without touching disk. Committed and
    /// rolled-back submissions remain in the journal for audit.
    @discardableResult
    public func cancel_pending() -> [UUID] {
        let ids = pending_submission_ids()
        for id in ids {
            guard let submission = submissions[id] else { continue }
            submissions[id] = submission.with_state(.withdrawn)
        }
        return ids
    }

    /// Owner-only prepared aggregate. The caller must apply Workspace read
    /// authorization before exposing any staged state to an agent.
    /// This uses the same planner and merge path as publication, but never writes.
    public func staged_plan() throws -> StandardMutationPlan? {
        guard !blocked else { throw StandardMutationCoordinationError.requires_recovery }
        let pending = order.compactMap { submissions[$0] }.filter {
            if case .pending = $0.state { return true }
            return false
        }
        guard !pending.isEmpty else { return nil }
        for submission in pending {
            for entry in submission.plan.entries {
                try entry.requireCurrent()
            }
        }
        if pending.count == 1 { return pending[0].plan }
        return try StandardMutationPlanner().plan(Self.combine(pending))
    }

    /// Owner-side virtual resource view. nil means the path has no staged change;
    /// .missing means it is staged for deletion. Copy/move are rejected rather
    /// than pretending their physical source/destination are an ordinary file edit.
    public func staged_state(at url: URL) throws -> StandardResourceState? {
        guard let plan = try staged_plan() else { return nil }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        for entry in plan.entries {
            let affected = entry.entry.targets.map {
                $0.standardizedFileURL.resolvingSymlinksInPath().path
            }
            guard affected.contains(path) else { continue }
            switch entry.entry {
            case .create_text, .replace_text, .edit_text, .delete:
                return entry.after
            case .copy, .move:
                throw StandardMutationCoordinationError.staged_visibility_unsupported(url)
            }
        }
        return nil
    }

    /// Rollback is a whole-publication operation: contributions that share one
    /// physical mutation record cannot safely be undone independently.
    /// All rollback targets receive conservative resource reservations.
    @discardableResult
    public func rollback(
        publication_id: UUID,
        options: StandardMutationRollbackApplyOptions = .init(),
        context: WriteExecutionContext = .init()
    ) throws -> StandardMutationRollbackResult {
        guard !blocked else { throw StandardMutationCoordinationError.requires_recovery }
        guard let publication = publications[publication_id] else {
            throw StandardMutationCoordinationError.unknown_publication(publication_id)
        }
        guard !rolled_back_publications.contains(publication_id) else {
            throw StandardMutationCoordinationError.publication_already_rolled_back(publication_id)
        }
        guard let plan = publication.result.rollback else {
            throw StandardMutationCoordinationError.publication_not_rollbackable(publication_id)
        }

        let footprints = plan.actions.flatMap { action -> [StandardMutationFootprint] in
            switch action {
            case .none:
                return []
            case .delete_created_file(let item):
                return [.resource(item.target)]
            case .restore_text(let item):
                return [.resource(item.target)]
            case .restore_data(let item):
                return [.resource(item.target)]
            case .move_resource(let item):
                return [.resource(item.source), .resource(item.destination)]
            }
        }
        for submission in order.compactMap({ submissions[$0] }) {
            guard case .pending = submission.state else { continue }
            if let collision = footprints.first(where: { footprint in
                submission.footprints.contains { footprint.overlaps($0) }
            }) {
                throw StandardMutationCoordinationError.conflict(
                    file: collision.file,
                    blocking_submission: submission.id
                )
            }
        }

        // The canonical rollback applier checks post-publication fingerprints.
        // A later mutation to the resource makes this fail, rather than erasing
        // unrelated subsequent edits. Selective rebase is deliberately absent.
        let result = StandardMutationRollbackApplier().apply(
            plan, options: options, context: context
        )
        rollback_results.append(result)
        if result.status == .applied {
            rolled_back_publications.insert(publication_id)
            for id in publication.submission_ids {
                guard let submission = submissions[id] else { continue }
                submissions[id] = submission.with_state(.rolled_back)
            }
        } else {
            // Even a failed rollback may have performed a partial side effect.
            // Owner reconciliation is mandatory before subsequent publication.
            blocked = true
        }
        return result
    }

    fileprivate func submit(
        participant_id: UUID,
        entries: [StandardMutationEntry],
        metadata: [String: String]
    ) throws -> StandardMutationSubmission {
        // Convenience for direct callers. Approved tool plans should instead
        // enter via submit(participant_id:plan:) with the exact previewed value.
        try require_participant(participant_id)
        guard !blocked else { throw StandardMutationCoordinationError.requires_recovery }
        let plan = try StandardMutationPlanner().plan(entries, metadata: metadata)
        return try submit(participant_id: participant_id, plan: plan)
    }

    fileprivate func submit(
        participant_id: UUID,
        plan: StandardMutationPlan
    ) throws -> StandardMutationSubmission {
        try require_participant(participant_id)
        guard !blocked else { throw StandardMutationCoordinationError.requires_recovery }

        // Admission operates on the caller's prepared plan; no fresh planning,
        // generated identity, or changed preview replaces it. The actor owns
        // conflict checks and publication rechecks current-state requirements.
        let per_entry_footprints = plan.entries.map { Self.footprints(for: $0.entry) }

        // A plan can contain different targets that overlap as resources, e.g. a
        // directory copy and an edit of a descendant. Reject the entire plan.
        for index in per_entry_footprints.indices {
            for later in per_entry_footprints.indices where later > index {
                if let colliding = per_entry_footprints[index].first(where: { left in
                    per_entry_footprints[later].contains { left.overlaps($0) }
                }) {
                    throw StandardMutationCoordinationError.overlapping_submission_footprints(
                        colliding.file
                    )
                }
            }
        }

        let footprints = per_entry_footprints.flatMap { $0 }
        let pending = order.compactMap { submissions[$0] }.filter {
            if case .pending = $0.state { return true }
            return false
        }
        for held in pending {
            if let colliding = footprints.first(where: { incoming in
                held.footprints.contains { incoming.overlaps($0) }
            }) {
                throw StandardMutationCoordinationError.conflict(
                    file: colliding.file, blocking_submission: held.id
                )
            }
        }

        let submission = StandardMutationSubmission(
            id: UUID(), participant_id: participant_id,
            plan: plan, footprints: footprints, state: .pending
        )
        // Detect option/mode incompatibility while submitting, not after a host
        // has approved proposals and attempts to publish them.
        let combined = try Self.combine(pending + [submission])
        if !pending.isEmpty {
            // Validate snapshot construction before accepting another proposal.
            // Participants should not receive a successful submission that can
            // only fail during a later publication for incompatible edit plans.
            _ = try StandardMutationPlanner().plan(combined)
        }
        submissions[submission.id] = submission
        order.append(submission.id)
        return submission
    }

    fileprivate func withdraw(participant_id: UUID, submission_id: UUID) throws {
        try require_participant(participant_id)
        guard let submission = submissions[submission_id] else {
            throw StandardMutationCoordinationError.unknown_submission(submission_id)
        }
        guard submission.participant_id == participant_id else {
            throw StandardMutationCoordinationError.submission_not_owned(submission_id)
        }
        guard case .pending = submission.state else {
            throw StandardMutationCoordinationError.submission_not_pending(submission_id)
        }
        submissions[submission_id] = submission.with_state(.withdrawn)
    }

    fileprivate func close(participant_id: UUID) throws {
        try require_participant(participant_id)
        for id in order {
            guard let submission = submissions[id], submission.participant_id == participant_id else { continue }
            if case .pending = submission.state {
                submissions[id] = submission.with_state(.withdrawn)
            }
        }
        participants[participant_id] = false
    }

    /// Owner-only boundary. The participant value does not expose this method.
    /// A partial filesystem failure blocks subsequent submissions until external recovery.
    public func publish(
        options: StandardMutationApplyOptions = .init(failure: .rollback_applied),
        context: WriteExecutionContext = .init()
    ) throws -> StandardMutationPublication? {
        guard !blocked else { throw StandardMutationCoordinationError.requires_recovery }
        let pending = order.compactMap { submissions[$0] }.filter {
            if case .pending = $0.state { return true }
            return false
        }
        guard !pending.isEmpty else { return nil }

        // Validate the *approved* snapshots, not merely a newly produced preview.
        // Without this, planning again at publication could silently absorb disk drift.
        for submission in pending {
            for entry in submission.plan.entries {
                try entry.requireCurrent()
            }
        }

        let publication_plan: StandardMutationPlan
        if pending.count == 1 {
            // Preserve the original approved plan, including its ID, metadata,
            // constraints and preview. Do not silently replan a lone submission.
            publication_plan = pending[0].plan
        } else {
            let combined = try Self.combine(pending)
            publication_plan = try StandardMutationPlanner().plan(combined)
        }
        // Resolve all source-to-publication links before touching the filesystem.
        // If the aggregate cannot account for a source operation, fail closed.
        let attribution = try Self.publication_attribution(
            for: pending, publication_plan: publication_plan
        )
        let result = StandardMutationApplier().apply(
            publication_plan, options: options, context: context
        )
        let applied_ids = Set(result.applied)
        let recorded_ids = Dictionary(
            uniqueKeysWithValues: zip(result.applied, result.records.map(\.id))
        )
        let contributions = attribution.map { contribution in
            StandardMutationContribution(
                submission_id: contribution.submission_id,
                participant_id: contribution.participant_id,
                source_plan_id: contribution.source_plan_id,
                source_plan_metadata: contribution.source_plan_metadata,
                entries: contribution.entries.map { source in
                    StandardMutationEntryContribution(
                        source_entry_id: source.source_entry_id,
                        published_entry_id: source.published_entry_id,
                        mutation_record_id: recorded_ids[source.published_entry_id],
                        was_applied: applied_ids.contains(source.published_entry_id)
                    )
                }
            )
        }
        for submission in pending {
            let state: StandardMutationSubmissionState
            switch result.status {
            case .applied: state = .committed(result.id)
            case .rolled_back: state = .rolled_back
            case .failed, .partial: state = .failed
            }
            submissions[submission.id] = submission.with_state(state)
        }
        // A failed or partial application may have left a filesystem side effect
        // before returning an error. Require owner-managed recovery before reuse.
        if result.status == .partial || result.status == .failed {
            blocked = true
        }
        let publication = StandardMutationPublication(
            result: result,
            submission_ids: pending.map(\.id),
            contributions: contributions
        )
        if result.status == .applied {
            publications[result.id] = publication
        }
        return publication
    }

    /// A verified relationship between original entries and aggregate entries.
    /// Target uniqueness is guaranteed by StandardMutationPlanner's output.
    private static func publication_attribution(
        for pending: [StandardMutationSubmission],
        publication_plan: StandardMutationPlan
    ) throws -> [StandardMutationContribution] {
        var published_by_target: [String: UUID] = [:]
        for entry in publication_plan.entries {
            let target = entry.entry.target.standardizedFileURL.path
            guard published_by_target.updateValue(entry.id, forKey: target) == nil else {
                throw StandardMutationCoordinationError.publication_attribution_missing(entry.target)
            }
        }
        return try pending.map { submission in
            let entries = try submission.plan.entries.map { source in
                let target = source.entry.target.standardizedFileURL.path
                guard let published_id = published_by_target[target] else {
                    throw StandardMutationCoordinationError.publication_attribution_missing(source.target)
                }
                return StandardMutationEntryContribution(
                    source_entry_id: source.id,
                    published_entry_id: published_id,
                    mutation_record_id: nil,
                    was_applied: false
                )
            }
            return .init(
                submission_id: submission.id,
                participant_id: submission.participant_id,
                source_plan_id: submission.plan.id,
                source_plan_metadata: submission.plan.metadata,
                entries: entries
            )
        }
    }

    private func require_participant(_ id: UUID) throws {
        guard let active = participants[id] else {
            throw StandardMutationCoordinationError.unknown_participant(id)
        }
        guard active else { throw StandardMutationCoordinationError.closed_participant(id) }
    }

    /// Incompatible/unknown edit shapes intentionally take a whole-file lease.
    /// This is conservative: no operation can escape coordination through an unknown footprint.
    private static func footprints(for entry: StandardMutationEntry) -> [StandardMutationFootprint] {
        switch entry {
        case .edit_text(let edit):
            // Sequential multi-step edits may address lines introduced by earlier steps;
            // such coordinates cannot safely be treated as original-revision ranges.
            if edit.operations.isEmpty || (edit.mode == .sequential && edit.operations.count > 1) {
                return [.resource(edit.target)]
            }
            return edit.operations.map { op in
                switch op {
                case .replaceLine(let line, _), .replaceLineGuarded(let line, _, _):
                    return .lines(edit.target, [.init(uncheckedStart: line, uncheckedEnd: line)])
                case .replaceLines(let range, _), .replaceLinesGuarded(let range, _, _),
                     .deleteLines(let range), .deleteLinesGuarded(let range, _):
                    return .lines(edit.target, [range])
                case .insertLines(_, let line), .insertLinesGuarded(_, let line, _):
                    return .insertions(edit.target, [line])
                default:
                    return .resource(edit.target)
                }
            }
        default:
            return entry.targets.map { .resource($0) }
        }
    }

    private static func combine(
        _ submissions: [StandardMutationSubmission]
    ) throws -> [StandardMutationEntry] {
        let entries = submissions.flatMap { $0.plan.entries.map(\.entry) }
        var groups: [String: [StandardMutationEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            // Primary target is sufficient: other occupied paths have already been reserved
            // as resource footprints and duplicate source/destination are refused at admission.
            let key = entry.target.standardizedFileURL.path
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        return try order.map { key in
            let group = groups[key] ?? []
            guard group.count > 1 else {
                guard let only = group.first else {
                    throw StandardMutationCoordinationError.unsupported_merge(URL(fileURLWithPath: key))
                }
                return only
            }
            var edits: [StandardEditText] = []
            for entry in group {
                guard case .edit_text(let edit) = entry else {
                    throw StandardMutationCoordinationError.unsupported_merge(entry.target)
                }
                edits.append(edit)
            }
            guard let first = edits.first else {
                throw StandardMutationCoordinationError.unsupported_merge(URL(fileURLWithPath: key))
            }
            guard edits.allSatisfy({ $0.options == first.options }) else {
                throw StandardMutationCoordinationError.incompatible_edit_options(first.target)
            }
            return .edit_text(.init(
                target: first.target,
                operations: edits.flatMap(\.operations),
                mode: .snapshot,
                // Each individual edit was already constraint-validated on the approved base.
                // The aggregate is only created after nonoverlap and drift checks.
                constraint: .unrestricted,
                options: first.options
            ))
        }
    }
}
