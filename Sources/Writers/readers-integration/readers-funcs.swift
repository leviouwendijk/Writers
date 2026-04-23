import Foundation
import Readers

public func standardReadText(
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
        return try TextFileReader(url).read(
            options: .init(
                decoding: .exact(.init(encoding)),
                missingFilePolicy: missingFilePolicy,
                newlineNormalization: newlineNormalization
            )
        ).text
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

public func standardReadData(
    at url: URL,
    missingFileReturnsEmpty: Bool = true
) throws -> Data {
    let missingFilePolicy: MissingFilePolicy = missingFileReturnsEmpty
        ? .returnEmpty
        : .throwError

    do {
        return try DataFileReader(url).read(
            options: .init(
                missingFilePolicy: missingFilePolicy
            )
        ).data
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
