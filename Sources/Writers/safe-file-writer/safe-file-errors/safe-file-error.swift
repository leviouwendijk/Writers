import Foundation
import Difference

public enum SafeFileError: Error, LocalizedError {
    case parentDirectoryMissing(URL)

    @available(*, deprecated, message: "Use overwriteConflict(_:)")
    case fileExistsAndNotBlank(URL)

    case overwriteConflict(SafeFileOverwriteConflict)
    case backupNotFound(URL)
    case nothingToRestore(URL)
    case io(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .parentDirectoryMissing(let url):
            return "Parent directory does not exist for: \(url.path)"

        case .fileExistsAndNotBlank(let url):
            return "Refusing to overwrite non-blank file without override: \(url.path)"

        case .overwriteConflict(let conflict):
            var message = """
            Refusing to overwrite non-blank file without override:
            \(conflict.url.path)
            """

            if let difference = conflict.difference {
                message += """

                

                \(DifferenceRenderer.Basic.render(difference))
                """
            }

            return message

        case .backupNotFound(let url):
            return "Backup not found at: \(url.path)"

        case .nothingToRestore(let url):
            return "No current file to replace at: \(url.path)"

        case .io(let underlying):
            return "I/O error: \(underlying.localizedDescription)"
        }
    }

    public var overwriteConflictValue: SafeFileOverwriteConflict? {
        switch self {
        case .overwriteConflict(let conflict):
            return conflict

        case .fileExistsAndNotBlank(let url):
            return .init(
                url: url,
                difference: nil
            )

        default:
            return nil
        }
    }

    public var difference: SafeFileDifference? {
        overwriteConflictValue?.difference
    }

    public var affectedURL: URL? {
        switch self {
        case .parentDirectoryMissing(let url):
            return url

        case .fileExistsAndNotBlank(let url):
            return url

        case .overwriteConflict(let conflict):
            return conflict.url

        case .backupNotFound(let url):
            return url

        case .nothingToRestore(let url):
            return url

        case .io:
            return nil
        }
    }
}
