import Foundation
import IO

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

        // One stat answers existence and, when the plan carries the metadata
        // of the file it read, whether that file is untouched: same identity,
        // size and mtime means no re-read and no hash. Any difference (a
        // `touch`, an atomic rewrite with the same bytes) falls back to the
        // content fingerprint. Assumes mtime resolution fine enough that a
        // same-size, same-inode rewrite within the window changes it (APFS:
        // nanoseconds; coarse-mtime filesystems are not covered).
        let current = try FileInspector(
            target
        ).inspect(
            followingSymlinks: true
        )

        if let before {
            guard current.existed else {
                throw WriteExecutionStalePlanError.current_missing(
                    target: target,
                    expected: before.fingerprint
                )
            }

            if let planned = beforeMetadata,
               planned.identity != nil,
               planned.identity == current.identity,
               planned.byteCount == current.byteCount,
               planned.modifiedAt == current.modifiedAt
            {
                return self
            }

            let currentFingerprint = try IntegratedReader.contentFingerprint(
                at: target,
                missingFileReturnsEmpty: false
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

        guard !current.existed else {
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
