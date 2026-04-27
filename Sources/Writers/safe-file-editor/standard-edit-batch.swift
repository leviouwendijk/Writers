import Difference
import Foundation
import Position

public enum StandardEditBatchError: Error, Sendable, LocalizedError {
    case unsupported_mode(StandardEditMode)
    case drift_detected(
        target: URL,
        expected: StandardContentFingerprint,
        actual: StandardContentFingerprint
    )

    public var errorDescription: String? {
        switch self {
        case .unsupported_mode(let mode):
            return "Standard edit batch tracing currently supports sequential mode only. Unsupported mode: \(mode.rawValue)."

        case .drift_detected(let target, let expected, let actual):
            return "Batch edit drift detected for \(target.path). Expected base fingerprint \(expected), but found \(actual)."
        }
    }
}

public indirect enum StandardEditLineOrigin: Sendable, Codable, Hashable {
    case original(Int)
    case inserted(step: Int, ordinal: Int)
    case replacement(
        step: Int,
        ordinal: Int,
        replaced: [StandardEditLineOrigin]
    )
}

public enum StandardEditBatchDiagnosticCode: String, Sendable, Codable, Hashable, CaseIterable {
    case no_changes
    case touches_prior_insertion
    case touches_prior_replacement
    case touches_same_original_range
}

public struct StandardEditBatchDiagnostic: Sendable, Codable, Hashable {
    public let code: StandardEditBatchDiagnosticCode
    public let step: Int
    public let message: String

    public init(
        code: StandardEditBatchDiagnosticCode,
        step: Int,
        message: String
    ) {
        self.code = code
        self.step = step
        self.message = message
    }
}

public struct StandardEditBatchSnapshot: Sendable, Codable, Hashable {
    public let fingerprint: StandardContentFingerprint
    public let lineCount: Int
    public let byteCount: Int

    public init(
        content: String
    ) {
        self.fingerprint = StandardContentFingerprint.fingerprint(
            for: content
        )
        self.lineCount = WriteTextLines(
            content
        ).lines.count
        self.byteCount = Data(
            content.utf8
        ).count
    }
}

public struct StandardEditBatchTouch: Sendable, Codable, Hashable {
    public let beforeRanges: [LineRange]
    public let afterRanges: [LineRange]
    public let originalRanges: [LineRange]
    public let priorStepIndexes: [Int]
    public let origins: [StandardEditLineOrigin]
    public let overlapsPriorStep: Bool

    public init(
        beforeRanges: [LineRange],
        afterRanges: [LineRange],
        originalRanges: [LineRange],
        priorStepIndexes: [Int],
        origins: [StandardEditLineOrigin],
        overlapsPriorStep: Bool
    ) {
        self.beforeRanges = beforeRanges
        self.afterRanges = afterRanges
        self.originalRanges = originalRanges
        self.priorStepIndexes = priorStepIndexes.sorted()
        self.origins = origins
        self.overlapsPriorStep = overlapsPriorStep
    }
}

public struct StandardEditBatchStep: Sendable, Codable, Hashable {
    public let index: Int
    public let operation: StandardEditOperation
    public let operationKind: StandardEditOperationKind
    public let before: StandardEditBatchSnapshot
    public let after: StandardEditBatchSnapshot
    public let touch: StandardEditBatchTouch
    public let diagnostics: [StandardEditBatchDiagnostic]

    public init(
        index: Int,
        operation: StandardEditOperation,
        before: StandardEditBatchSnapshot,
        after: StandardEditBatchSnapshot,
        touch: StandardEditBatchTouch,
        diagnostics: [StandardEditBatchDiagnostic]
    ) {
        self.index = index
        self.operation = operation
        self.operationKind = operation.kind
        self.before = before
        self.after = after
        self.touch = touch
        self.diagnostics = diagnostics
    }
}

public struct StandardEditBatchPlan: Sendable, Codable, Hashable {
    public let target: URL
    public let mode: StandardEditMode
    public let operations: [StandardEditOperation]
    public let base: StandardEditBatchSnapshot
    public let final: StandardEditBatchSnapshot
    public let steps: [StandardEditBatchStep]
    public let result: StandardEditResult
    public let diagnostics: [StandardEditBatchDiagnostic]

    public init(
        target: URL,
        mode: StandardEditMode,
        operations: [StandardEditOperation],
        base: StandardEditBatchSnapshot,
        final: StandardEditBatchSnapshot,
        steps: [StandardEditBatchStep],
        result: StandardEditResult,
        diagnostics: [StandardEditBatchDiagnostic]
    ) {
        self.target = target
        self.mode = mode
        self.operations = operations
        self.base = base
        self.final = final
        self.steps = steps
        self.result = result
        self.diagnostics = diagnostics
    }

    public var report: StandardEditBatchReport {
        .init(
            self
        )
    }
}

public struct StandardEditBatchStepReport: Sendable, Codable, Hashable {
    public let index: Int
    public let operationKind: StandardEditOperationKind
    public let beforeFingerprint: StandardContentFingerprint
    public let afterFingerprint: StandardContentFingerprint
    public let beforeRanges: [LineRange]
    public let afterRanges: [LineRange]
    public let originalRanges: [LineRange]
    public let priorStepIndexes: [Int]
    public let overlapsPriorStep: Bool
    public let diagnosticCodes: [StandardEditBatchDiagnosticCode]

    public init(
        _ step: StandardEditBatchStep
    ) {
        self.index = step.index
        self.operationKind = step.operationKind
        self.beforeFingerprint = step.before.fingerprint
        self.afterFingerprint = step.after.fingerprint
        self.beforeRanges = step.touch.beforeRanges
        self.afterRanges = step.touch.afterRanges
        self.originalRanges = step.touch.originalRanges
        self.priorStepIndexes = step.touch.priorStepIndexes
        self.overlapsPriorStep = step.touch.overlapsPriorStep
        self.diagnosticCodes = step.diagnostics.map(\.code)
    }
}

public struct StandardEditBatchReport: Sendable, Codable, Hashable {
    public let target: URL
    public let mode: StandardEditMode
    public let operationCount: Int
    public let stepCount: Int
    public let baseFingerprint: StandardContentFingerprint
    public let finalFingerprint: StandardContentFingerprint
    public let changedLineCount: Int
    public let insertedLineCount: Int
    public let deletedLineCount: Int
    public let originalChangedLineRanges: [LineRange]
    public let editedChangedLineRanges: [LineRange]
    public let steps: [StandardEditBatchStepReport]
    public let diagnosticCodes: [StandardEditBatchDiagnosticCode]

    public init(
        _ plan: StandardEditBatchPlan
    ) {
        self.target = plan.target
        self.mode = plan.mode
        self.operationCount = plan.operations.count
        self.stepCount = plan.steps.count
        self.baseFingerprint = plan.base.fingerprint
        self.finalFingerprint = plan.final.fingerprint
        self.changedLineCount = plan.result.changeCount
        self.insertedLineCount = plan.result.insertions
        self.deletedLineCount = plan.result.deletions
        self.originalChangedLineRanges = plan.result.originalChangedLineRanges
        self.editedChangedLineRanges = plan.result.editedChangedLineRanges
        self.steps = plan.steps.map(StandardEditBatchStepReport.init)
        self.diagnosticCodes = plan.diagnostics.map(\.code)
    }
}

public struct StandardEditBatchApplyPlan: Sendable {
    public let editPlan: StandardEditPlan
    public let batch: StandardEditBatchPlan
    public let options: StandardEditApplyOptions

    public init(
        editPlan: StandardEditPlan,
        batch: StandardEditBatchPlan,
        options: StandardEditApplyOptions = .init()
    ) throws {
        guard batch.operations == editPlan.operations else {
            throw StandardEditApplyError.preview_operations_mismatch(
                expected: editPlan.operations.map(\.kind),
                actual: batch.operations.map(\.kind)
            )
        }

        self.editPlan = editPlan
        self.batch = batch
        self.options = options
    }
}

public struct StandardEditBatchPlanner: Sendable {
    struct Hunk: Sendable, Hashable {
        let before: Range<Int>
        let after: Range<Int>
    }

    public let target: URL

    public init(
        target: URL
    ) {
        self.target = target
    }

    public func plan(
        operations: [StandardEditOperation],
        baseContent: String,
        mode: StandardEditMode = .sequential
    ) throws -> StandardEditBatchPlan {
        guard mode == .sequential else {
            throw StandardEditBatchError.unsupported_mode(
                mode
            )
        }

        var content = baseContent
        var origins = initialOrigins(
            for: baseContent
        )
        var steps: [StandardEditBatchStep] = []
        var touchedOriginalLines = Set<Int>()

        for pair in operations.enumerated() {
            let stepIndex = pair.offset + 1
            let operation = pair.element
            let beforeContent = content
            let beforeOrigins = origins
            let afterContent = try operation.applying(
                to: beforeContent
            )
            let difference = WriteDifference.lines(
                old: beforeContent,
                new: afterContent,
                oldName: "\(target.lastPathComponent) (step \(stepIndex) before)",
                newName: "\(target.lastPathComponent) (step \(stepIndex) after)"
            )
            let hunks = changedHunks(
                for: difference
            )
            let removedOrigins = originsTouched(
                hunks: hunks,
                origins: beforeOrigins
            )
            let priorStepIndexes = removedOrigins.priorStepIndexes(
                before: stepIndex
            )
            let originalLines = removedOrigins.originalLineNumbers()
            var diagnostics = diagnostics(
                stepIndex: stepIndex,
                beforeContent: beforeContent,
                afterContent: afterContent,
                origins: removedOrigins,
                priorStepIndexes: priorStepIndexes,
                previousOriginalLines: touchedOriginalLines
            )

            touchedOriginalLines.formUnion(
                originalLines
            )

            origins = applying(
                hunks: hunks,
                beforeOrigins: beforeOrigins,
                stepIndex: stepIndex
            )
            content = afterContent

            if hunks.isEmpty,
               diagnostics.isEmpty {
                diagnostics.append(
                    .init(
                        code: .no_changes,
                        step: stepIndex,
                        message: "Operation \(stepIndex) produced no textual changes."
                    )
                )
            }

            steps.append(
                .init(
                    index: stepIndex,
                    operation: operation,
                    before: .init(
                        content: beforeContent
                    ),
                    after: .init(
                        content: afterContent
                    ),
                    touch: .init(
                        beforeRanges: ranges(
                            hunks.map(\.before)
                        ),
                        afterRanges: ranges(
                            hunks.map(\.after)
                        ),
                        originalRanges: ranges(
                            originalLines
                        ),
                        priorStepIndexes: priorStepIndexes,
                        origins: removedOrigins,
                        overlapsPriorStep: !priorStepIndexes.isEmpty
                    ),
                    diagnostics: diagnostics
                )
            )
        }

        let result = StandardEditor(
            target
        ).makeResult(
            operations: operations,
            original: baseContent,
            edited: content,
            writeResult: nil
        )
        let diagnostics = steps.flatMap(\.diagnostics)

        return .init(
            target: target,
            mode: mode,
            operations: operations,
            base: .init(
                content: baseContent
            ),
            final: .init(
                content: content
            ),
            steps: steps,
            result: result,
            diagnostics: diagnostics
        )
    }
}

public extension StandardEditor {
    func batch(
        _ operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditBatchPlan {
        let original = try IntegratedReader.text(
            at: url,
            encoding: encoding,
            missingFileReturnsEmpty: true,
            normalizeNewlines: false
        )

        return try StandardEditBatchPlanner(
            target: url
        ).plan(
            operations: operations,
            baseContent: original,
            mode: mode
        )
    }

    func batch(
        _ plan: StandardEditPlan,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditBatchPlan {
        let batch = try batch(
            plan.operations,
            mode: plan.mode,
            encoding: encoding
        )

        try plan.constraint.validate(
            batch.result
        )

        return batch
    }

    func prepareBatch(
        _ editPlan: StandardEditPlan,
        options: StandardEditApplyOptions = .init()
    ) throws -> StandardEditBatchApplyPlan {
        try .init(
            editPlan: editPlan,
            batch: batch(
                editPlan,
                encoding: options.encoding
            ),
            options: options
        )
    }

    @discardableResult
    func apply(
        _ applyPlan: StandardEditBatchApplyPlan
    ) throws -> StandardEditResult {
        let current = try IntegratedReader.text(
            at: url,
            encoding: applyPlan.options.encoding,
            missingFileReturnsEmpty: true,
            normalizeNewlines: false
        )
        let actual = StandardContentFingerprint.fingerprint(
            for: current
        )

        guard actual == applyPlan.batch.base.fingerprint else {
            throw StandardEditBatchError.drift_detected(
                target: url,
                expected: applyPlan.batch.base.fingerprint,
                actual: actual
            )
        }

        return try apply(
            StandardEditApplyPlan(
                editPlan: applyPlan.editPlan,
                preview: applyPlan.batch.result,
                options: applyPlan.options
            )
        )
    }
}

private extension StandardEditBatchPlanner {
    func initialOrigins(
        for content: String
    ) -> [StandardEditLineOrigin] {
        WriteTextLines(
            content
        ).lines.indices.map { index in
            .original(
                index + 1
            )
        }
    }

    func changedHunks(
        for difference: SafeFileDifference
    ) -> [Hunk] {
        var hunks: [Hunk] = []

        var beforeLine = 0
        var afterLine = 0

        var beforeStart: Int?
        var afterStart: Int?
        var beforeEnd: Int?
        var afterEnd: Int?

        func beginIfNeeded() {
            if beforeStart == nil {
                beforeStart = beforeLine
            }

            if afterStart == nil {
                afterStart = afterLine
            }
        }

        func flush() {
            guard let resolvedBeforeStart = beforeStart,
                  let resolvedAfterStart = afterStart
            else {
                return
            }

            let resolvedBeforeEnd = beforeEnd ?? beforeLine
            let resolvedAfterEnd = afterEnd ?? afterLine

            guard resolvedBeforeStart <= resolvedBeforeEnd,
                  resolvedAfterStart <= resolvedAfterEnd
            else {
                beforeStart = nil
                afterStart = nil
                beforeEnd = nil
                afterEnd = nil
                return
            }

            hunks.append(
                .init(
                    before: resolvedBeforeStart..<resolvedBeforeEnd,
                    after: resolvedAfterStart..<resolvedAfterEnd
                )
            )

            beforeStart = nil
            afterStart = nil
            beforeEnd = nil
            afterEnd = nil
        }

        for line in difference.lines {
            switch line.operation {
            case .equal:
                flush()
                beforeLine += 1
                afterLine += 1

            case .delete:
                beginIfNeeded()
                beforeLine += 1
                beforeEnd = beforeLine

            case .insert:
                beginIfNeeded()
                afterLine += 1
                afterEnd = afterLine
            }
        }

        flush()

        return hunks
    }

    func originsTouched(
        hunks: [Hunk],
        origins: [StandardEditLineOrigin]
    ) -> [StandardEditLineOrigin] {
        var out: [StandardEditLineOrigin] = []

        for hunk in hunks {
            guard hunk.before.lowerBound < hunk.before.upperBound else {
                continue
            }

            let lowerBound = max(
                0,
                hunk.before.lowerBound
            )
            let upperBound = min(
                origins.count,
                hunk.before.upperBound
            )

            guard lowerBound < upperBound else {
                continue
            }

            out.append(
                contentsOf: origins[lowerBound..<upperBound]
            )
        }

        return out
    }

    func applying(
        hunks: [Hunk],
        beforeOrigins: [StandardEditLineOrigin],
        stepIndex: Int
    ) -> [StandardEditLineOrigin] {
        guard !hunks.isEmpty else {
            return beforeOrigins
        }

        var out: [StandardEditLineOrigin] = []
        var cursor = 0

        for hunk in hunks {
            if cursor < hunk.before.lowerBound {
                out.append(
                    contentsOf: beforeOrigins[cursor..<hunk.before.lowerBound]
                )
            }

            let removed = hunk.before.lowerBound < hunk.before.upperBound
                ? Array(
                    beforeOrigins[
                        hunk.before.lowerBound..<min(
                            beforeOrigins.count,
                            hunk.before.upperBound
                        )
                    ]
                )
                : []

            let insertedCount = max(
                0,
                hunk.after.upperBound - hunk.after.lowerBound
            )

            for ordinal in 0..<insertedCount {
                if removed.isEmpty {
                    out.append(
                        .inserted(
                            step: stepIndex,
                            ordinal: ordinal
                        )
                    )
                } else {
                    out.append(
                        .replacement(
                            step: stepIndex,
                            ordinal: ordinal,
                            replaced: removed
                        )
                    )
                }
            }

            cursor = hunk.before.upperBound
        }

        if cursor < beforeOrigins.count {
            out.append(
                contentsOf: beforeOrigins[cursor..<beforeOrigins.count]
            )
        }

        return out
    }

    func diagnostics(
        stepIndex: Int,
        beforeContent: String,
        afterContent: String,
        origins: [StandardEditLineOrigin],
        priorStepIndexes: [Int],
        previousOriginalLines: Set<Int>
    ) -> [StandardEditBatchDiagnostic] {
        var diagnostics: [StandardEditBatchDiagnostic] = []

        if beforeContent == afterContent {
            diagnostics.append(
                .init(
                    code: .no_changes,
                    step: stepIndex,
                    message: "Operation \(stepIndex) produced no textual changes."
                )
            )
        }

        if origins.containsInsertedOrigin {
            diagnostics.append(
                .init(
                    code: .touches_prior_insertion,
                    step: stepIndex,
                    message: "Operation \(stepIndex) touched content inserted by an earlier operation."
                )
            )
        }

        if origins.containsReplacementOrigin {
            diagnostics.append(
                .init(
                    code: .touches_prior_replacement,
                    step: stepIndex,
                    message: "Operation \(stepIndex) touched content replaced by an earlier operation."
                )
            )
        }

        if !previousOriginalLines.intersection(
            origins.originalLineNumbers()
        ).isEmpty {
            diagnostics.append(
                .init(
                    code: .touches_same_original_range,
                    step: stepIndex,
                    message: "Operation \(stepIndex) touched original lines already touched by an earlier operation."
                )
            )
        }

        return diagnostics
    }

    func ranges(
        _ ranges: [Range<Int>]
    ) -> [LineRange] {
        ranges.compactMap { range in
            guard range.lowerBound < range.upperBound else {
                return nil
            }

            return LineRange(
                uncheckedStart: range.lowerBound + 1,
                uncheckedEnd: range.upperBound
            )
        }
    }

    func ranges(
        _ lines: Set<Int>
    ) -> [LineRange] {
        let sorted = lines.sorted()

        guard !sorted.isEmpty else {
            return []
        }

        var out: [LineRange] = []
        var start = sorted[0]
        var previous = sorted[0]

        for line in sorted.dropFirst() {
            if line == previous + 1 {
                previous = line
                continue
            }

            out.append(
                .init(
                    uncheckedStart: start,
                    uncheckedEnd: previous
                )
            )

            start = line
            previous = line
        }

        out.append(
            .init(
                uncheckedStart: start,
                uncheckedEnd: previous
            )
        )

        return out
    }
}

private extension Array where Element == StandardEditLineOrigin {
    var containsInsertedOrigin: Bool {
        contains {
            $0.containsInsertedOrigin
        }
    }

    var containsReplacementOrigin: Bool {
        contains {
            $0.containsReplacementOrigin
        }
    }

    func originalLineNumbers() -> Set<Int> {
        reduce(
            into: Set<Int>()
        ) { partial, origin in
            partial.formUnion(
                origin.originalLineNumbers()
            )
        }
    }

    func priorStepIndexes(
        before step: Int
    ) -> [Int] {
        let values = reduce(
            into: Set<Int>()
        ) { partial, origin in
            partial.formUnion(
                origin.stepIndexes()
            )
        }.filter {
            $0 < step
        }

        return values.sorted()
    }
}

private extension StandardEditLineOrigin {
    var containsInsertedOrigin: Bool {
        switch self {
        case .original:
            return false

        case .inserted:
            return true

        case .replacement(_, _, let replaced):
            return replaced.containsInsertedOrigin
        }
    }

    var containsReplacementOrigin: Bool {
        switch self {
        case .original,
             .inserted:
            return false

        case .replacement:
            return true
        }
    }

    func originalLineNumbers() -> Set<Int> {
        switch self {
        case .original(let line):
            return [
                line
            ]

        case .inserted:
            return []

        case .replacement(_, _, let replaced):
            return replaced.originalLineNumbers()
        }
    }

    func stepIndexes() -> Set<Int> {
        switch self {
        case .original:
            return []

        case .inserted(let step, _):
            return [
                step
            ]

        case .replacement(let step, _, let replaced):
            var out = Set<Int>()
            out.insert(
                step
            )
            out.formUnion(
                replaced.reduce(
                    into: Set<Int>()
                ) { partial, origin in
                    partial.formUnion(
                        origin.stepIndexes()
                    )
                }
            )
            return out
        }
    }
}
