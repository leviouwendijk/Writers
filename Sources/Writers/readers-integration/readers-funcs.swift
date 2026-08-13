import Foundation
import Readers

public enum IntegratedReader {
    public static func text(
        at url: URL,
        encoding: String.Encoding,
        missingFileReturnsEmpty: Bool = true,
        normalizeNewlines: Bool = false
    ) throws -> String {
        let missingFilePolicy: MissingFilePolicy = missingFileReturnsEmpty
            ? .returnEmpty
            : .throwError

        let newlineNormalization: NewlineNormalization = normalizeNewlines
            ? .unix
            : .preserve

        do {
            return try TextFileReader(
                url
            ).read(
                options: .init(
                    decoding: .exact(
                        TextEncoding(
                            encoding
                        )
                    ),
                    missingFilePolicy: missingFilePolicy,
                    newlineNormalization: newlineNormalization,
                    cachePolicy: .uncached
                )
            ).text
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
        let missingFilePolicy: MissingFilePolicy = missingFileReturnsEmpty
            ? .returnEmpty
            : .throwError

        do {
            return try DataFileReader(
                url
            ).read(
                options: .init(
                    missingFilePolicy: missingFilePolicy,
                    cachePolicy: .uncached
                )
            ).data
        } catch {
            throw SafeFileError.io(
                underlying: error
            )
        }
    }
}
