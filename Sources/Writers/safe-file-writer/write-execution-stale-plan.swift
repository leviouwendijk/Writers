import Foundation

public enum WriteExecutionStalePlanError: Error, Sendable, LocalizedError, Hashable {
    case current_missing(
        target: URL,
        expected: StandardContentFingerprint
    )

    case current_appeared(
        target: URL
    )

    case current_mismatch(
        target: URL,
        expected: StandardContentFingerprint,
        actual: StandardContentFingerprint
    )

    public var errorDescription: String? {
        switch self {
        case .current_missing(let target, let expected):
            return "Write plan is stale for \(target.path). Expected current fingerprint \(expected), but the file no longer exists."

        case .current_appeared(let target):
            return "Write plan is stale for \(target.path). The plan expected to create a new file, but the file now exists."

        case .current_mismatch(let target, let expected, let actual):
            return "Write plan is stale for \(target.path). Expected current fingerprint \(expected), but found \(actual)."
        }
    }
}

public extension WritePlan {
    func validatingCurrentState(
        policy: WriteExecutionStalePlanPolicy = .require_current_matches_plan
    ) throws -> Self {
        guard policy == .require_current_matches_plan else {
            return self
        }

        let fm = FileManager.default

        if let before {
            guard fm.fileExists(
                atPath: target.path
            ) else {
                throw WriteExecutionStalePlanError.current_missing(
                    target: target,
                    expected: before.fingerprint
                )
            }

            let currentData = try IntegratedReader.data(
                at: target,
                missingFileReturnsEmpty: false
            )
            let currentFingerprint = StandardContentFingerprint.fingerprint(
                for: currentData
            )

            guard currentFingerprint == before.fingerprint else {
                throw WriteExecutionStalePlanError.current_mismatch(
                    target: target,
                    expected: before.fingerprint,
                    actual: currentFingerprint
                )
            }

            return self
        }

        guard !fm.fileExists(
            atPath: target.path
        ) else {
            throw WriteExecutionStalePlanError.current_appeared(
                target: target
            )
        }

        return self
    }

    func validateCurrentState(
        policy: WriteExecutionStalePlanPolicy = .require_current_matches_plan
    ) throws {
        _ = try validatingCurrentState(
            policy: policy
        )
    }
}
