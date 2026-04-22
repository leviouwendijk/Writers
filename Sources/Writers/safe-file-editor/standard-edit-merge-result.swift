import Foundation
import Difference

public struct StandardEditMergeResult: Sendable {
    public let target: URL
    public let strategy: StandardEditMergeStrategy
    public let currentContent: String
    public let mergedContent: String
    public let difference: SafeFileDifference
    public let writeResult: SafeWriteResult?

    public init(
        target: URL,
        strategy: StandardEditMergeStrategy,
        currentContent: String,
        mergedContent: String,
        difference: SafeFileDifference,
        writeResult: SafeWriteResult?
    ) {
        self.target = target
        self.strategy = strategy
        self.currentContent = currentContent
        self.mergedContent = mergedContent
        self.difference = difference
        self.writeResult = writeResult
    }

    public var hasChanges: Bool {
        difference.hasChanges
    }

    public var performedWrite: Bool {
        writeResult != nil
    }

    public var currentFingerprint: StandardContentFingerprint {
        StandardContentFingerprint.fingerprint(
            for: currentContent
        )
    }

    public var mergedFingerprint: StandardContentFingerprint {
        StandardContentFingerprint.fingerprint(
            for: mergedContent
        )
    }

    public func diffLayout(
        options: SafeFileDiffRenderOptions = .unified
    ) -> SafeFileDiffLayout {
        DifferenceRenderer.layout(
            difference,
            options: options
        )
    }

    public func renderedDifference(
        options: SafeFileDiffRenderOptions = .unified
    ) -> String {
        DifferenceRenderer.render(
            difference,
            options: options
        )
    }

    public func renderedDifference<Renderer: DifferenceRendering>(
        using renderer: Renderer.Type
    ) -> String {
        Renderer.render(difference)
    }
}
