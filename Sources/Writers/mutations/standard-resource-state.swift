import Foundation

public enum StandardResourceState: Sendable, Codable, Hashable {
    case missing
    case text(StandardTextState)
    case data(StandardDataState)

    public var exists: Bool {
        switch self {
        case .missing:
            return false

        case .text,
             .data:
            return true
        }
    }

    public var fingerprint: StandardContentFingerprint? {
        switch self {
        case .missing:
            return nil

        case .text(let state):
            return state.fingerprint

        case .data(let state):
            return state.fingerprint
        }
    }

    public var snapshot: WriteMutationSnapshot? {
        switch self {
        case .missing:
            return nil

        case .text(let state):
            return .init(
                content: state.content,
                storeContent: true,
                encoding: state.encoding
            )

        case .data(let state):
            return .init(
                data: state.content,
                storeContent: true
            )
        }
    }

    public var textContent: String? {
        switch self {
        case .text(let state):
            return state.content

        case .missing,
             .data:
            return nil
        }
    }

    public var dataContent: Data? {
        switch self {
        case .text(let state):
            return state.data

        case .data(let state):
            return state.content

        case .missing:
            return nil
        }
    }

    public static func read(
        at target: URL,
        encoding: String.Encoding = .utf8
    ) throws -> Self {
        let target = target.standardizedFileURL

        guard FileManager.default.fileExists(
            atPath: target.path
        ) else {
            return .missing
        }

        let data = try IntegratedReader.data(
            at: target,
            missingFileReturnsEmpty: false
        )

        if let content = String(
            data: data,
            encoding: encoding
        ) {
            return .text(
                .init(
                    content: content,
                    encoding: encoding
                )
            )
        }

        return .data(
            .init(
                content: data
            )
        )
    }

    public static func text(
        _ content: String,
        encoding: String.Encoding = .utf8
    ) -> Self {
        .text(
            .init(
                content: content,
                encoding: encoding
            )
        )
    }

    public static func data(
        _ content: Data
    ) -> Self {
        .data(
            .init(
                content: content
            )
        )
    }

    public func requireText(
        target: URL
    ) throws -> StandardTextState {
        switch self {
        case .text(let state):
            return state

        case .missing:
            throw StandardMutationError.target_missing(
                target
            )

        case .data:
            throw StandardMutationError.target_not_text(
                target
            )
        }
    }

    public func requireExisting(
        target: URL
    ) throws {
        guard exists else {
            throw StandardMutationError.target_missing(
                target
            )
        }
    }

    public func requireCurrent(
        at target: URL,
        encoding: String.Encoding = .utf8
    ) throws {
        let current = try Self.read(
            at: target,
            encoding: encoding
        )

        guard current.fingerprint == fingerprint else {
            throw StandardMutationError.drift_detected(
                target: target,
                expected: fingerprint,
                actual: current.fingerprint
            )
        }
    }
}

public struct StandardTextState: Sendable, Codable, Hashable {
    public let content: String
    public let encodingRawValue: UInt
    public let fingerprint: StandardContentFingerprint
    public let bytes: Int
    public let lines: Int

    public init(
        content: String,
        encoding: String.Encoding = .utf8
    ) {
        let data = content.data(
            using: encoding
        ) ?? Data(
            content.utf8
        )

        self.content = content
        self.encodingRawValue = encoding.rawValue
        self.fingerprint = StandardContentFingerprint.fingerprint(
            for: data
        )
        self.bytes = data.count
        self.lines = Self.lineCount(
            content
        )
    }

    public var data: Data {
        content.data(
            using: encoding
        ) ?? Data(
            content.utf8
        )
    }

    public var encoding: String.Encoding {
        String.Encoding(
            rawValue: encodingRawValue
        )
    }

    private static func lineCount(
        _ content: String
    ) -> Int {
        guard !content.isEmpty else {
            return 0
        }

        return content
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .count
    }
}

public struct StandardDataState: Sendable, Codable, Hashable {
    public let content: Data
    public let fingerprint: StandardContentFingerprint
    public let bytes: Int

    public init(
        content: Data
    ) {
        self.content = content
        self.fingerprint = StandardContentFingerprint.fingerprint(
            for: content
        )
        self.bytes = content.count
    }
}
