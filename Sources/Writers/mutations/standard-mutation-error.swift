import Foundation

public enum StandardMutationError: Error, Sendable, LocalizedError {
    case empty_entries
    case duplicate_target(URL)
    /// Two entries of one pass touch a directory and something inside it.
    case nested_targets(outer: URL, inner: URL)
    case target_missing(URL)
    case target_exists(URL)
    case target_not_text(URL)
    case target_not_copyable_resource(URL)
    case target_not_movable_resource(URL)
    case metadata_drift_detected(target: URL)
    case unsupported_rollback_action
    case drift_detected(
        target: URL,
        expected: StandardContentFingerprint?,
        actual: StandardContentFingerprint?
    )
    /// A file is larger than the destination volume can hold (FAT32: 4 GiB − 1).
    case exceeds_file_size_limit(source: URL, destination: URL, size: Int64, limit: Int64)
    /// The pass writes more to a volume than it has free.
    case insufficient_space(volume: URL, needed: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .empty_entries:
            return "Mutation pass cannot be empty."

        case .duplicate_target(let target):
            return "Mutation pass contains duplicate target \(target.path). Merge same-file changes into one entry before planning."

        case .nested_targets(let outer, let inner):
            return "Mutation pass changes \(outer.path) and, in another entry, \(inner.path) inside it. Split them into separate passes: first the entries inside, then the directory."

        case .target_missing(let target):
            return "Mutation target is missing: \(target.path)"

        case .target_exists(let target):
            return "Mutation target already exists: \(target.path)"

        case .target_not_text(let target):
            return "Mutation target is not readable as text: \(target.path)"

        case .target_not_copyable_resource(let target):
            return "Mutation source is not a copyable regular file or directory: \(target.path)"

        case .target_not_movable_resource(let target):
            return "Mutation source is not a movable regular file or directory: \(target.path)"

        case .metadata_drift_detected(let target):
            return "Mutation metadata drift detected for \(target.path). The resource changed since planning."

        case .unsupported_rollback_action:
            return "Mutation rollback action is not supported by this pass."

        case .drift_detected(let target, let expected, let actual):
            let expectedText = expected.map(String.init(describing:)) ?? "missing"
            let actualText = actual.map(String.init(describing:)) ?? "missing"

            return "Mutation drift detected for \(target.path). Expected \(expectedText), found \(actualText)."

        case .exceeds_file_size_limit(let source, let destination, let size, let limit):
            return "\(source.path) holds a file of \(Self.bytes(size)); the volume of \(destination.path) holds files up to \(Self.bytes(limit)) (FAT32 limit?). Nothing was written."

        case .insufficient_space(let volume, let needed, let available):
            return "This pass writes \(Self.bytes(needed)) to the volume of \(volume.path), which has \(Self.bytes(available)) free. Nothing was written."
        }
    }

    private static func bytes(
        _ value: Int64
    ) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}
