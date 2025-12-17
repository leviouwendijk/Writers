import Foundation

public protocol SafelyWritable: Sendable {
    var url: URL { get }
}
