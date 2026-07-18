import Foundation

public struct ReadFixtureTool: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }
    public func call(path: String) throws -> String {
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw CocoaError(.fileReadNoPermission) }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
