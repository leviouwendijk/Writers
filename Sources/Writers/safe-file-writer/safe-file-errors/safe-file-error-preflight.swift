import Foundation

public enum SafePreflightError: Error, LocalizedError {
    case refusingToOverwrite([URL])

    public var errorDescription: String? {
        switch self {
        case .refusingToOverwrite(let urls):
            let list = urls.map { "• \($0.path)" }.joined(separator: "\n")
            return """
            Refusing to overwrite existing non-blank files:
            \(list)
            Pass overrideExisting=true to allow (backups will be created by default).
            """
        }
    }
}
