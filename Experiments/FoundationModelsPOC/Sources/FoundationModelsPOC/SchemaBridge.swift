import Foundation

public indirect enum CanonicalSchema: Equatable, Sendable {
    case string, integer, number, boolean
    case object(properties: [String: CanonicalSchema], required: Set<String>)
    case array(CanonicalSchema), enumeration([String])
}

public enum SchemaBridgeError: LocalizedError, Equatable { case unsupported(keyword: String, path: String)
    public var errorDescription: String? { switch self { case let .unsupported(keyword, path): "Unsupported JSON Schema keyword \(keyword) at \(path)" } }
}

public enum SchemaBridge {
    public static func parse(_ value: Any, path: String = "$") throws -> CanonicalSchema {
        guard let object = value as? [String: Any] else { throw SchemaBridgeError.unsupported(keyword: "non-object", path: path) }
        for keyword in ["anyOf", "$ref", "additionalProperties", "minimum", "maximum"] where object[keyword] != nil {
            throw SchemaBridgeError.unsupported(keyword: keyword, path: path)
        }
        switch object["type"] as? String {
        case "string": return object["enum"].map { .enumeration($0 as? [String] ?? []) } ?? .string
        case "integer": return .integer
        case "number": return .number
        case "boolean": return .boolean
        case "array": return .array(try parse(object["items"] as Any, path: "\(path).items"))
        case "object":
            let properties = object["properties"] as? [String: Any] ?? [:]
            return .object(properties: try properties.reduce(into: [:]) { $0[$1.key] = try parse($1.value, path: "\(path).properties.\($1.key)") }, required: Set(object["required"] as? [String] ?? []))
        default: throw SchemaBridgeError.unsupported(keyword: "type", path: path)
        }
    }
}
