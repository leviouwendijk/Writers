import Foundation
import IO

public struct StandardCopyResource: Sendable, Codable, Hashable {
    public var source: URL
    public var destination: URL
    public var createParentDirectories: Bool

    public init(
        source: URL,
        destination: URL,
        createParentDirectories: Bool = true
    ) {
        self.source = source.standardizedFileURL
        self.destination = destination.standardizedFileURL
        self.createParentDirectories = createParentDirectories
    }
}

public struct StandardCopyPlan: Sendable, Codable, Hashable {
    public let source: StandardMoveResourceState
    public let destination: StandardMoveResourceState

    public init(
        source: StandardMoveResourceState,
        destination: StandardMoveResourceState
    ) {
        self.source = source
        self.destination = destination
    }

    public func requireCurrent() throws {
        try source.requireCurrent()
        try destination.requireCurrent()
    }
}
