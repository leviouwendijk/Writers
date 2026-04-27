import Foundation

public enum StandardMutationError: Error, Sendable, LocalizedError {
    case empty_entries
    case duplicate_target(URL)
    case target_missing(URL)
    case target_exists(URL)
    case target_not_text(URL)
    case unsupported_rollback_action
    case drift_detected(
        target: URL,
        expected: StandardContentFingerprint?,
        actual: StandardContentFingerprint?
    )

    public var errorDescription: String? {
        switch self {
        case .empty_entries:
            return "Mutation pass cannot be empty."

        case .duplicate_target(let target):
            return "Mutation pass contains duplicate target \(target.path). Merge same-file changes into one entry before planning."

        case .target_missing(let target):
            return "Mutation target is missing: \(target.path)"

        case .target_exists(let target):
            return "Mutation target already exists: \(target.path)"

        case .target_not_text(let target):
            return "Mutation target is not readable as text: \(target.path)"

        case .unsupported_rollback_action:
            return "Mutation rollback action is not supported by this pass."

        case .drift_detected(let target, let expected, let actual):
            let expectedText = expected.map(String.init(describing:)) ?? "missing"
            let actualText = actual.map(String.init(describing:)) ?? "missing"

            return "Mutation drift detected for \(target.path). Expected \(expectedText), found \(actualText)."
        }
    }
}
