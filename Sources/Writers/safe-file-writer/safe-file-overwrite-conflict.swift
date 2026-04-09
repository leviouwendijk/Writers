import Foundation
import Difference

public struct SafeFileOverwriteConflict: Sendable, Hashable {
    public let url: URL
    public let difference: SafeFileDifference?

    public init(
        url: URL,
        difference: SafeFileDifference?
    ) {
        self.url = url
        self.difference = difference
    }

    public var hasDifference: Bool {
        difference != nil
    }

    public var hasChanges: Bool {
        difference?.hasChanges ?? false
    }
}

public extension SafeFileOverwriteConflict {
    @inlinable
    func layout(
        options: SafeFileDiffRenderOptions = .unified
    ) -> SafeFileDiffLayout? {
        guard let difference else {
            return nil
        }

        return DifferenceRenderer.layout(
            difference,
            options: options
        )
    }
}
