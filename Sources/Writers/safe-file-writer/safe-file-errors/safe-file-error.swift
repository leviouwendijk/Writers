import Foundation

public enum SafeFileError: Error, LocalizedError {
    case parentDirectoryMissing(URL)
    case fileExistsAndNotBlank(URL)
    case backupNotFound(URL)
    case nothingToRestore(URL)
    case io(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .parentDirectoryMissing(let url):
            return "Parent directory does not exist for: \(url.path)"
        case .fileExistsAndNotBlank(let url):
            return "Refusing to overwrite non-blank file without override: \(url.path)"
        case .backupNotFound(let url):
            return "Backup not found at: \(url.path)"
        case .nothingToRestore(let url):
            return "No current file to replace at: \(url.path)"
        case .io(let underlying):
            return "I/O error: \(underlying.localizedDescription)"
        }
    }
}

