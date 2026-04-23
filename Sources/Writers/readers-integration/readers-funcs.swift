import Foundation
import Readers

public enum IntegratedReader {
    public static func text(
        at url: URL,
        encoding: String.Encoding,
        missingFileReturnsEmpty: Bool = true,
        normalizeNewlines: Bool = false
    ) throws -> String {
        do {
            return try StandardReading.text(
                at: url,
                encoding: encoding,
                missingFileReturnsEmpty: missingFileReturnsEmpty,
                normalizeNewlines: normalizeNewlines
            )
        } catch let error as TextReadError {
            throw SafeFileError.io(
                underlying: error
            )
        } catch {
            throw SafeFileError.io(
                underlying: error
            )
        }
    }

    public static func data(
        at url: URL,
        missingFileReturnsEmpty: Bool = true
    ) throws -> Data {
        do {
            return try StandardReading.data(
                at: url,
                missingFileReturnsEmpty: missingFileReturnsEmpty,
            )
        } catch let error as DataReadError {
            throw SafeFileError.io(
                underlying: error
            )
        } catch {
            throw SafeFileError.io(
                underlying: error
            )
        }
    }
}
