import Foundation

public enum StandardEditDriftPolicy: String, Sendable, Codable, Hashable, CaseIterable {
    case allow
    case require_original_fingerprint
}

public enum StandardEditApplyErrorCode: String, Sendable, Codable, Hashable, CaseIterable {
    case preview_target_mismatch
    case preview_already_applied
    case preview_operations_mismatch
    case drift_detected
}

public enum StandardEditApplyError: Error, Sendable, LocalizedError {
    case preview_target_mismatch(
        previewTarget: URL,
        editorTarget: URL
    )
    case preview_already_applied(
        target: URL
    )
    case preview_operations_mismatch(
        expected: [StandardEditOperationKind],
        actual: [StandardEditOperationKind]
    )
    case drift_detected(
        target: URL,
        expected: StandardContentFingerprint,
        actual: StandardContentFingerprint
    )

    public var code: StandardEditApplyErrorCode {
        switch self {
        case .preview_target_mismatch:
            return .preview_target_mismatch

        case .preview_already_applied:
            return .preview_already_applied

        case .preview_operations_mismatch:
            return .preview_operations_mismatch

        case .drift_detected:
            return .drift_detected
        }
    }

    public var errorDescription: String? {
        switch self {
        case .preview_target_mismatch(let previewTarget, let editorTarget):
            return "Edit preview target \(previewTarget.path) does not match editor target \(editorTarget.path)."

        case .preview_already_applied(let target):
            return "Edit preview for \(target.path) already has a write result and cannot be applied as an approval preview."

        case .preview_operations_mismatch(let expected, let actual):
            return "Edit preview operations do not match the approved edit plan. Expected \(expected.map(\.rawValue)), found \(actual.map(\.rawValue))."

        case .drift_detected(let target, let expected, let actual):
            return "Edit drift detected for \(target.path). Expected original fingerprint \(expected), but found \(actual)."
        }
    }
}

public struct StandardEditApplyOptions: Sendable {
    public var encoding: String.Encoding
    public var write: SafeWriteOptions
    public var drift: StandardEditDriftPolicy

    public init(
        encoding: String.Encoding = .utf8,
        write: SafeWriteOptions = .overwrite,
        drift: StandardEditDriftPolicy = .require_original_fingerprint
    ) {
        self.encoding = encoding
        self.write = write
        self.drift = drift
    }
}

public struct StandardEditApplyPlan: Sendable {
    public let editPlan: StandardEditPlan
    public let preview: StandardEditResult
    public let options: StandardEditApplyOptions

    public init(
        editPlan: StandardEditPlan,
        preview: StandardEditResult,
        options: StandardEditApplyOptions = .init()
    ) {
        self.editPlan = editPlan
        self.preview = preview
        self.options = options
    }
}

public extension StandardEditor {
    func preview(
        _ plan: StandardEditPlan,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try plan.constraint.validated(
            preview(
                plan.operations,
                mode: plan.mode,
                encoding: encoding
            )
        )
    }

    func preview(
        _ operation: StandardEditOperation,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try preview(
            StandardEditPlan(
                operation: operation,
                mode: mode,
                constraint: constraint
            ),
            encoding: encoding
        )
    }

    func preview(
        _ operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try preview(
            StandardEditPlan(
                operations: operations,
                mode: mode,
                constraint: constraint
            ),
            encoding: encoding
        )
    }

    func prepareApply(
        _ editPlan: StandardEditPlan,
        options: StandardEditApplyOptions = .init()
    ) throws -> StandardEditApplyPlan {
        try prepareApply(
            preview(
                editPlan,
                encoding: options.encoding
            ),
            plan: editPlan,
            options: options
        )
    }

    func prepareApply(
        _ preview: StandardEditResult,
        plan editPlan: StandardEditPlan,
        options: StandardEditApplyOptions = .init()
    ) throws -> StandardEditApplyPlan {
        let applyPlan = StandardEditApplyPlan(
            editPlan: editPlan,
            preview: preview,
            options: options
        )

        try validateApplyPlan(
            applyPlan
        )

        return applyPlan
    }

    @discardableResult
    func apply(
        _ preview: StandardEditResult,
        plan editPlan: StandardEditPlan,
        options: StandardEditApplyOptions = .init()
    ) throws -> StandardEditResult {
        try apply(
            prepareApply(
                preview,
                plan: editPlan,
                options: options
            )
        )
    }

    @discardableResult
    func apply(
        _ applyPlan: StandardEditApplyPlan
    ) throws -> StandardEditResult {
        try validateApplyPlan(
            applyPlan
        )

        let preview = applyPlan.preview

        guard preview.hasChanges else {
            return preview
        }

        try requireNoDrift(
            preview,
            policy: applyPlan.options.drift,
            encoding: applyPlan.options.encoding
        )

        let writeResult = try writer.write(
            preview.editedContent,
            encoding: applyPlan.options.encoding,
            options: applyPlan.options.write
        )

        let result = StandardEditResult(
            target: preview.target,
            operations: preview.operations,
            originalContent: preview.originalContent,
            editedContent: preview.editedContent,
            difference: preview.difference,
            changes: preview.changes,
            writeResult: writeResult
        )

        try applyPlan.editPlan.constraint.validate(
            result
        )

        return result
    }

    @discardableResult
    func edit(
        _ plan: StandardEditPlan,
        options: StandardEditApplyOptions = .init()
    ) throws -> StandardEditResult {
        try apply(
            prepareApply(
                plan,
                options: options
            )
        )
    }

    @discardableResult
    func edit(
        _ operation: StandardEditOperation,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init(),
        constraint: StandardEditConstraint,
        drift: StandardEditDriftPolicy = .require_original_fingerprint
    ) throws -> StandardEditResult {
        try edit(
            StandardEditPlan(
                operation: operation,
                mode: mode,
                constraint: constraint
            ),
            options: .init(
                encoding: encoding,
                write: options,
                drift: drift
            )
        )
    }

    @discardableResult
    func edit(
        _ operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init(),
        constraint: StandardEditConstraint,
        drift: StandardEditDriftPolicy = .require_original_fingerprint
    ) throws -> StandardEditResult {
        try edit(
            StandardEditPlan(
                operations: operations,
                mode: mode,
                constraint: constraint
            ),
            options: .init(
                encoding: encoding,
                write: options,
                drift: drift
            )
        )
    }
}

private extension StandardEditor {
    func validateApplyPlan(
        _ applyPlan: StandardEditApplyPlan
    ) throws {
        try validateApplyTarget(
            applyPlan.preview
        )
        try validateApplyPreviewIsUnwritten(
            applyPlan.preview
        )
        try validateApplyOperations(
            preview: applyPlan.preview,
            plan: applyPlan.editPlan
        )

        try applyPlan.editPlan.constraint.validate(
            applyPlan.preview
        )
    }

    func validateApplyTarget(
        _ preview: StandardEditResult
    ) throws {
        guard sameEditTarget(
            preview.target,
            url
        ) else {
            throw StandardEditApplyError.preview_target_mismatch(
                previewTarget: preview.target,
                editorTarget: url
            )
        }
    }

    func validateApplyPreviewIsUnwritten(
        _ preview: StandardEditResult
    ) throws {
        guard !preview.performedWrite else {
            throw StandardEditApplyError.preview_already_applied(
                target: preview.target
            )
        }
    }

    func validateApplyOperations(
        preview: StandardEditResult,
        plan: StandardEditPlan
    ) throws {
        guard preview.operations == plan.operations else {
            throw StandardEditApplyError.preview_operations_mismatch(
                expected: plan.operations.map(\.kind),
                actual: preview.operations.map(\.kind)
            )
        }
    }

    func requireNoDrift(
        _ preview: StandardEditResult,
        policy: StandardEditDriftPolicy,
        encoding: String.Encoding
    ) throws {
        switch policy {
        case .allow:
            return

        case .require_original_fingerprint:
            let current = try IntegratedReader.text(
                at: url,
                encoding: encoding,
                missingFileReturnsEmpty: true,
                normalizeNewlines: false
            )

            let actual = StandardContentFingerprint.fingerprint(
                for: current
            )

            guard actual == preview.originalFingerprint else {
                throw StandardEditApplyError.drift_detected(
                    target: url,
                    expected: preview.originalFingerprint,
                    actual: actual
                )
            }
        }
    }

    func sameEditTarget(
        _ lhs: URL,
        _ rhs: URL
    ) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
