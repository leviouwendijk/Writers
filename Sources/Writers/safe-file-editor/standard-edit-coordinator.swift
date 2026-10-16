import Foundation
import Position

public enum StandardEditCoordinationError: Error, Sendable {
    case invalid_phase
    case duplicate_file(URL)
    case unknown_file(URL)
    case duplicate_mutator_name(String)
    case unknown_mutator(UUID)
    case stopped_mutator(UUID)
    case unknown_acquisition(UUID)
    case acquisition_not_owned(UUID)
    case unknown_mutation(UUID)
    case unsupported_operation(StandardEditOperationKind)
    case scope_violation(URL)
    case invalid_source(URL)
    case overlapping_mutations(URL, UUID, UUID)
    case active_mutators([UUID])
    case stale_construction
    case external_change(URL)
    case representation_mismatch(URL)
    case partial_write(failed: URL, completed: [URL], cause: String)
}

public enum StandardEditConflictPolicy: Sendable {
    case first_acquirer
}

public enum StandardEditAcquisitionState: Sendable {
    case granted
    case contested(winner_mutator_id: UUID, winner_acquisition_id: UUID)
}

public struct StandardEditAcquisition: Sendable, Identifiable {
    public let id: UUID
    public let mutator_id: UUID
    public let file: URL
    public let scope: StandardEditScope
    public let state: StandardEditAcquisitionState
}

public enum StandardEditMutationState: Sendable {
    case submitted
    case contested(winner_mutator_id: UUID)
    case withdrawn(reason: String?)
    case committed(commit_id: UUID)
}

public struct StandardEditMutation: Sendable, Identifiable {
    public let id: UUID
    public let mutator_id: UUID
    public let acquisition_id: UUID
    public let file: URL
    public let operation: StandardEditOperation
    public let comment: String?
    public let state: StandardEditMutationState

    fileprivate func with_state(_ next: StandardEditMutationState) -> Self {
        .init(
            id: id,
            mutator_id: mutator_id,
            acquisition_id: acquisition_id,
            file: file,
            operation: operation,
            comment: comment,
            state: next
        )
    }
}

public enum StandardEditPiece: Sendable {
    case source(byte_range: Range<Int>)
    case replacement(mutation_id: UUID, original_byte_range: Range<Int>, bytes: Data)
}

public struct StandardEditFileConstruction: Sendable {
    public let file: URL
    public let base_revision_id: UUID
    public let pieces: [StandardEditPiece]
    public let included_mutation_ids: [UUID]

    public func materialize(source_bytes: Data) -> Data {
        var result = Data()
        for piece in pieces {
            switch piece {
            case .source(let range):
                result.append(source_bytes.subdata(in: range))
            case .replacement(_, _, let bytes):
                result.append(bytes)
            }
        }
        return result
    }
}

public struct StandardEditConstruction: Sendable {
    public let id: UUID
    public let generation: UInt64
    public let files: [StandardEditFileConstruction]
    public let mutations: [StandardEditMutation]
}

public struct StandardEditCommittedFile: Sendable {
    public let file: URL
    public let result: SafeWriteResult
}

public struct StandardEditCommit: Sendable {
    public let id: UUID
    public let files: [StandardEditCommittedFile]
    public let mutations: [StandardEditMutation]
}

public struct StandardEditCoordinationStatus: Sendable {
    public let registered_mutators: Int
    public let active_mutators: Int
    public let granted_acquisitions: Int
    public let contested_acquisitions: Int
    public let submitted_mutations: Int
    public let contested_mutations: Int
}

public struct StandardEditMutator: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    private let coordinator: StandardEditCoordinator

    fileprivate init(id: UUID, name: String, coordinator: StandardEditCoordinator) {
        self.id = id
        self.name = name
        self.coordinator = coordinator
    }

    public func acquire(file: URL, scope: StandardEditScope) async throws -> StandardEditAcquisition {
        try await coordinator.acquire(mutator_id: id, file: file, scope: scope)
    }

    @discardableResult
    public func submit(
        acquisition: StandardEditAcquisition,
        operation: StandardEditOperation,
        comment: String? = nil
    ) async throws -> StandardEditMutation {
        try await coordinator.submit(
            mutator_id: id,
            acquisition_id: acquisition.id,
            operation: operation,
            comment: comment
        )
    }

    public func stop() async throws {
        try await coordinator.stop(mutator_id: id)
    }

    public func abort(comment: String? = nil) async {
        await coordinator.abort(mutator_id: id, comment: comment)
    }
}

public actor StandardEditCoordinator {
    private enum Phase {
        case unread
        case accepting
        case sealed
        case written
    }

    private struct Source {
        let url: URL
        let revision_id: UUID
        let bytes: Data
        let text: String
        let lines: [String]
        let starts: [Int]
    }

    private struct MutatorRecord {
        let name: String
        var active: Bool
    }

    private struct Edit {
        let mutation_id: UUID
        let span: Range<Int>
        let replacement: Data
    }

    private var phase: Phase = .unread
    private let conflict_policy: StandardEditConflictPolicy
    private var sources: [URL: Source] = [:]
    private var mutators: [UUID: MutatorRecord] = [:]
    private var mutator_names = Set<String>()
    private var acquisitions: [StandardEditAcquisition] = []
    private var mutations: [StandardEditMutation] = []
    private var generation: UInt64 = 0

    public init(conflict_policy: StandardEditConflictPolicy = .first_acquirer) {
        self.conflict_policy = conflict_policy
    }

    @discardableResult
    public func read(_ files: [URL]) throws -> [URL] {
        guard phase == .unread, !files.isEmpty else {
            throw StandardEditCoordinationError.invalid_phase
        }
        var loaded: [URL: Source] = [:]
        for file in files {
            let url = file.standardizedFileURL.resolvingSymlinksInPath()
            guard url.isFileURL else {
                throw StandardEditCoordinationError.invalid_source(url)
            }
            guard loaded[url] == nil else {
                throw StandardEditCoordinationError.duplicate_file(url)
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8),
                  !text.contains("\r") else {
                throw StandardEditCoordinationError.invalid_source(url)
            }
            var starts = [0]
            for (index, byte) in data.enumerated() where byte == 10 {
                if index + 1 < data.count {
                    starts.append(index + 1)
                }
            }
            if data.isEmpty {
                starts = []
            }
            var lines = text.components(separatedBy: "\n")
            if data.isEmpty {
                lines = []
            } else if data.last == 10 {
                lines.removeLast()
            }
            loaded[url] = .init(
                url: url,
                revision_id: UUID(),
                bytes: data,
                text: text,
                lines: lines,
                starts: starts
            )
        }
        sources = loaded
        phase = .accepting
        return loaded.keys.sorted(by: { $0.path < $1.path })
    }

    public func mutator(name: String) throws -> StandardEditMutator {
        guard phase == .accepting else {
            throw StandardEditCoordinationError.invalid_phase
        }
        guard !name.isEmpty, !mutator_names.contains(name) else {
            throw StandardEditCoordinationError.duplicate_mutator_name(name)
        }
        let id = UUID()
        mutator_names.insert(name)
        mutators[id] = .init(name: name, active: true)
        return .init(id: id, name: name, coordinator: self)
    }

    public func seal() throws {
        guard phase == .accepting else {
            throw StandardEditCoordinationError.invalid_phase
        }
        phase = .sealed
    }

    public func status() -> StandardEditCoordinationStatus {
        .init(
            registered_mutators: mutators.count,
            active_mutators: mutators.values.filter(\.active).count,
            granted_acquisitions: acquisitions.filter { acquisition in
                if case .granted = acquisition.state { return true }
                return false
            }.count,
            contested_acquisitions: acquisitions.filter { acquisition in
                if case .contested = acquisition.state { return true }
                return false
            }.count,
            submitted_mutations: mutations.filter { mutation in
                if case .submitted = mutation.state { return true }
                return false
            }.count,
            contested_mutations: mutations.filter { mutation in
                if case .contested = mutation.state { return true }
                return false
            }.count
        )
    }

    public func journal() -> [StandardEditMutation] {
        mutations
    }

    fileprivate func acquire(
        mutator_id: UUID,
        file: URL,
        scope: StandardEditScope
    ) throws -> StandardEditAcquisition {
        try require_active(mutator_id)
        guard phase == .accepting || phase == .sealed else {
            throw StandardEditCoordinationError.invalid_phase
        }
        let url = file.standardizedFileURL.resolvingSymlinksInPath()
        guard let source = sources[url] else {
            throw StandardEditCoordinationError.unknown_file(url)
        }
        guard valid(scope: scope, line_count: source.lines.count) else {
            throw StandardEditCoordinationError.scope_violation(url)
        }
        var state: StandardEditAcquisitionState = .granted
        for existing in acquisitions where existing.file == url {
            guard case .granted = existing.state else { continue }
            if overlaps(existing.scope, scope) {
                state = .contested(
                    winner_mutator_id: existing.mutator_id,
                    winner_acquisition_id: existing.id
                )
                break
            }
        }
        let receipt = StandardEditAcquisition(
            id: UUID(),
            mutator_id: mutator_id,
            file: url,
            scope: scope,
            state: state
        )
        acquisitions.append(receipt)
        return receipt
    }

    fileprivate func submit(
        mutator_id: UUID,
        acquisition_id: UUID,
        operation: StandardEditOperation,
        comment: String?
    ) throws -> StandardEditMutation {
        try require_active(mutator_id)
        guard phase == .accepting || phase == .sealed else {
            throw StandardEditCoordinationError.invalid_phase
        }
        guard let acquisition = acquisitions.first(where: { $0.id == acquisition_id }) else {
            throw StandardEditCoordinationError.unknown_acquisition(acquisition_id)
        }
        guard acquisition.mutator_id == mutator_id else {
            throw StandardEditCoordinationError.acquisition_not_owned(acquisition_id)
        }
        guard let source = sources[acquisition.file] else {
            throw StandardEditCoordinationError.unknown_file(acquisition.file)
        }
        guard contains(scope: acquisition.scope, operation: operation) else {
            throw StandardEditCoordinationError.scope_violation(acquisition.file)
        }
        _ = try normalized_edit(operation, mutation_id: UUID(), source: source)
        let state: StandardEditMutationState
        switch acquisition.state {
        case .granted:
            state = .submitted
        case .contested(let winner, _):
            state = .contested(winner_mutator_id: winner)
        }
        let mutation = StandardEditMutation(
            id: UUID(),
            mutator_id: mutator_id,
            acquisition_id: acquisition_id,
            file: acquisition.file,
            operation: operation,
            comment: comment,
            state: state
        )
        mutations.append(mutation)
        generation &+= 1
        return mutation
    }

    fileprivate func stop(mutator_id: UUID) throws {
        try require_active(mutator_id)
        mutators[mutator_id]?.active = false
    }

    fileprivate func abort(mutator_id: UUID, comment: String?) {
        guard mutators[mutator_id]?.active == true else { return }
        mutators[mutator_id]?.active = false
        // Keep the journal, but remove the abandoned changes from construction.
        for index in mutations.indices where mutations[index].mutator_id == mutator_id {
            if case .submitted = mutations[index].state {
                mutations[index] = mutations[index].with_state(.withdrawn(reason: comment))
                generation &+= 1
            }
        }
        // Leases remain reserved until the coordinator's write barrier.
    }

    public func withdraw(mutation_id: UUID, comment: String? = nil) throws {
        guard phase == .accepting || phase == .sealed else {
            throw StandardEditCoordinationError.invalid_phase
        }
        guard let index = mutations.firstIndex(where: { $0.id == mutation_id }) else {
            throw StandardEditCoordinationError.unknown_mutation(mutation_id)
        }
        guard case .submitted = mutations[index].state else {
            throw StandardEditCoordinationError.invalid_phase
        }
        mutations[index] = mutations[index].with_state(.withdrawn(reason: comment))
        generation &+= 1
    }

    public func construct() throws -> StandardEditConstruction {
        guard phase == .accepting || phase == .sealed else {
            throw StandardEditCoordinationError.invalid_phase
        }
        let files = try sources.keys.sorted(by: { $0.path < $1.path }).map {
            try construct_file($0)
        }
        return .init(id: UUID(), generation: generation, files: files, mutations: mutations)
    }

    public func construct(file: URL) throws -> StandardEditFileConstruction {
        try construct_file(file.standardizedFileURL.resolvingSymlinksInPath())
    }

    public func write(
        _ construction: StandardEditConstruction,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditCommit {
        guard phase == .sealed else {
            throw StandardEditCoordinationError.invalid_phase
        }
        let active = mutators.filter { $0.value.active }.map(\.key)
        guard active.isEmpty else {
            throw StandardEditCoordinationError.active_mutators(active)
        }
        guard construction.generation == generation,
              construction.files.count == sources.count else {
            throw StandardEditCoordinationError.stale_construction
        }
        // Verify the submitted document is still exactly the coordinator's candidate.
        let current = try construct()
        guard current.files.count == construction.files.count,
              zip(current.files, construction.files).allSatisfy({ left, right in
                  left.file == right.file &&
                  left.included_mutation_ids == right.included_mutation_ids &&
                  left.base_revision_id == right.base_revision_id
              }) else {
            throw StandardEditCoordinationError.stale_construction
        }
        for file in construction.files {
            guard let source = sources[file.file],
                  try Data(contentsOf: file.file) == source.bytes else {
                throw StandardEditCoordinationError.external_change(file.file)
            }
        }
        var completed: [StandardEditCommittedFile] = []
        for file in construction.files where !file.included_mutation_ids.isEmpty {
            guard let source = sources[file.file] else {
                throw StandardEditCoordinationError.unknown_file(file.file)
            }
            do {
                let materialized = file.materialize(source_bytes: source.bytes)
                guard materialized != source.bytes else { continue }
                let result = try StandardWriter(file.file).write(
                    materialized,
                    options: options
                )
                completed.append(.init(file: file.file, result: result))
            } catch {
                throw StandardEditCoordinationError.partial_write(
                    failed: file.file,
                    completed: completed.map(\.file),
                    cause: String(describing: error)
                )
            }
        }
        let commit_id = UUID()
        mutations = mutations.map { mutation in
            if case .submitted = mutation.state {
                return mutation.with_state(.committed(commit_id: commit_id))
            }
            return mutation
        }
        phase = .written
        return .init(id: commit_id, files: completed, mutations: mutations)
    }

    private func construct_file(_ file: URL) throws -> StandardEditFileConstruction {
        guard phase == .accepting || phase == .sealed else {
            throw StandardEditCoordinationError.invalid_phase
        }
        guard let source = sources[file] else {
            throw StandardEditCoordinationError.unknown_file(file)
        }
        let accepted = mutations.filter { mutation in
            guard mutation.file == file else { return false }
            if case .submitted = mutation.state { return true }
            return false
        }
        var edits = try accepted.map { mutation in
            try normalized_edit(mutation.operation, mutation_id: mutation.id, source: source)
        }
        let expected = try StandardEditBatchPlanner(target: file).plan(
            operations: accepted.map(\.operation),
            baseContent: source.text,
            mode: .snapshot
        )
        edits.sort { left, right in
            if left.span.lowerBound == right.span.lowerBound {
                return left.span.upperBound < right.span.upperBound
            }
            return left.span.lowerBound < right.span.lowerBound
        }
        var pieces: [StandardEditPiece] = []
        var position = 0
        var previous: Edit?
        for edit in edits {
            if let previous,
               edit.span.lowerBound < position ||
               (edit.span.isEmpty && previous.span.isEmpty && edit.span.lowerBound == previous.span.lowerBound) {
                throw StandardEditCoordinationError.overlapping_mutations(file, previous.mutation_id, edit.mutation_id)
            }
            if position < edit.span.lowerBound {
                pieces.append(.source(byte_range: position..<edit.span.lowerBound))
            }
            pieces.append(.replacement(
                mutation_id: edit.mutation_id,
                original_byte_range: edit.span,
                bytes: edit.replacement
            ))
            position = edit.span.upperBound
            previous = edit
        }
        if position < source.bytes.count {
            pieces.append(.source(byte_range: position..<source.bytes.count))
        }
        let result = StandardEditFileConstruction(
            file: file,
            base_revision_id: source.revision_id,
            pieces: pieces,
            included_mutation_ids: accepted.map(\.id)
        )
        guard result.materialize(source_bytes: source.bytes) == Data(expected.result.editedContent.utf8) else {
            throw StandardEditCoordinationError.representation_mismatch(file)
        }
        return result
    }

    private func require_active(_ id: UUID) throws {
        guard let record = mutators[id] else {
            throw StandardEditCoordinationError.unknown_mutator(id)
        }
        guard record.active else {
            throw StandardEditCoordinationError.stopped_mutator(id)
        }
    }

    private func normalized_edit(
        _ operation: StandardEditOperation,
        mutation_id: UUID,
        source: Source
    ) throws -> Edit {
        try operation.validateLinePayloadShape(operationIndex: 1)
        // Existing snapshot operation validation also checks expected text and insertion guards.
        _ = try operation.applyingSnapshot(to: source.text)
        let line_count = source.lines.count
        func line_start(_ line: Int) -> Int? {
            guard line >= 1, line <= line_count + 1 else { return nil }
            return line == line_count + 1 ? source.bytes.count : source.starts[line - 1]
        }
        func replacement_bytes(_ lines: [String], ending_at end: Int) -> Data {
            var text = lines.joined(separator: "\n")
            if !lines.isEmpty, end < source.bytes.count || source.bytes.last == 10 {
                text += "\n"
            }
            return Data(text.utf8)
        }
        switch operation {
        case .replaceLine(let line, let content),
             .replaceLineGuarded(let line, _, let content):
            guard let start = line_start(line), let end = line_start(line + 1), line <= line_count else {
                throw StandardEditCoordinationError.scope_violation(source.url)
            }
            return .init(mutation_id: mutation_id, span: start..<end, replacement: replacement_bytes([content], ending_at: end))
        case .replaceLines(let range, let lines),
             .replaceLinesGuarded(let range, _, let lines):
            guard let start = line_start(range.start), let end = line_start(range.end + 1), range.end <= line_count else {
                throw StandardEditCoordinationError.scope_violation(source.url)
            }
            let effective_start = lines.isEmpty && end == source.bytes.count &&
                source.bytes.last != 10 && start > 0 ? start - 1 : start
            return .init(mutation_id: mutation_id, span: effective_start..<end, replacement: replacement_bytes(lines, ending_at: end))
        case .deleteLines(let range), .deleteLinesGuarded(let range, _):
            guard let start = line_start(range.start), let end = line_start(range.end + 1), range.end <= line_count else {
                throw StandardEditCoordinationError.scope_violation(source.url)
            }
            let effective_start = end == source.bytes.count &&
                source.bytes.last != 10 && start > 0 ? start - 1 : start
            return .init(mutation_id: mutation_id, span: effective_start..<end, replacement: Data())
        case .insertLines(let lines, let at),
             .insertLinesGuarded(let lines, let at, _):
            guard let offset = line_start(at) else {
                throw StandardEditCoordinationError.scope_violation(source.url)
            }
            var text = lines.joined(separator: "\n")
            if !lines.isEmpty {
                if at <= line_count || source.bytes.last == 10 {
                    text += "\n"
                } else if !source.bytes.isEmpty {
                    text = "\n" + text
                }
            }
            return .init(mutation_id: mutation_id, span: offset..<offset, replacement: Data(text.utf8))
        default:
            throw StandardEditCoordinationError.unsupported_operation(operation.kind)
        }
    }

    private func valid(scope: StandardEditScope, line_count: Int) -> Bool {
        switch scope {
        case .file: return true
        case .lines(let ranges):
            return !ranges.isEmpty && ranges.allSatisfy { $0.start >= 1 && $0.start <= $0.end && $0.end <= line_count }
        case .insertions(let positions):
            return !positions.isEmpty && positions.allSatisfy { $0 >= 1 && $0 <= line_count + 1 }
        }
    }

    private func contains(scope: StandardEditScope, operation: StandardEditOperation) -> Bool {
        let footprint: StandardEditScope
        switch operation {
        case .replaceLine(let line, _), .replaceLineGuarded(let line, _, _):
            footprint = .lines([.init(uncheckedStart: line, uncheckedEnd: line)])
        case .replaceLines(let range, _), .replaceLinesGuarded(let range, _, _),
             .deleteLines(let range), .deleteLinesGuarded(let range, _):
            footprint = .lines([range])
        case .insertLines(_, let line), .insertLinesGuarded(_, let line, _):
            footprint = .insertions([line])
        default: return false
        }
        switch (scope, footprint) {
        case (.file, _): return true
        case (.lines(let allowed), .lines(let actual)):
            return actual.allSatisfy { span in
                allowed.contains { $0.start <= span.start && $0.end >= span.end }
            }
        case (.insertions(let allowed), .insertions(let actual)):
            return actual.allSatisfy { allowed.contains($0) }
        default: return false
        }
    }

    private func overlaps(_ a: StandardEditScope, _ b: StandardEditScope) -> Bool {
        switch (a, b) {
        case (.file, _), (_, .file): return true
        case (.lines(let left), .lines(let right)):
            return left.contains { x in right.contains { y in x.start <= y.end && y.start <= x.end } }
        case (.insertions(let left), .insertions(let right)):
            return left.contains { right.contains($0) }
        case (.lines(let ranges), .insertions(let positions)),
             (.insertions(let positions), .lines(let ranges)):
            return positions.contains { line in ranges.contains { $0.start <= line && line <= $0.end } }
        }
    }
}
