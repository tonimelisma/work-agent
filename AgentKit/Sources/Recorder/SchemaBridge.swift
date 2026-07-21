import Foundation
import FoundationModels

// REQ: agent-loop-implementation.md §2 — host Tool contract / Foundation Models bridge.
// Migrated from Experiments/FoundationModelsPOC. Converts a raw JSON Schema (as decoded
// from `Any`) into Apple's `GenerationSchema`, for tool definitions that arrive as data
// rather than as a Swift `@Generable` type — the case MCP tools land in later.

public indirect enum CanonicalSchema: Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case object(properties: [String: CanonicalSchema], required: Set<String>)
    case array(CanonicalSchema)
    case enumeration([String])
}

public enum SchemaBridgeError: LocalizedError, Equatable, Sendable {
    case unsupported(keyword: String, path: String)
    case invalid(keyword: String, path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupported(keyword, path):
            "Unsupported JSON Schema keyword \(keyword) at \(path)"
        case let .invalid(keyword, path, reason):
            "Invalid JSON Schema keyword \(keyword) at \(path): \(reason)"
        }
    }
}

public enum SchemaBridge {
    public static func parse(_ value: Any, path: String = "$") throws -> CanonicalSchema {
        guard let object = value as? [String: Any] else {
            throw SchemaBridgeError.invalid(
                keyword: "schema",
                path: path,
                reason: "expected an object"
            )
        }

        let recognizedKeywords: Set<String> = [
            "type", "enum", "items", "properties", "required", "additionalProperties",
        ]
        if let keyword = object.keys.filter({ !recognizedKeywords.contains($0) }).sorted().first {
            throw SchemaBridgeError.unsupported(keyword: keyword, path: path)
        }

        switch object["type"] as? String {
        case "string":
            try rejectUnexpectedKeywords(in: object, allowed: ["type", "enum"], path: path)
            guard let enumValue = object["enum"] else { return .string }
            guard let values = enumValue as? [Any], !values.isEmpty else {
                throw SchemaBridgeError.invalid(
                    keyword: "enum",
                    path: path,
                    reason: "expected a nonempty array of strings"
                )
            }
            let strings = try values.enumerated().map { index, value in
                guard let string = value as? String else {
                    throw SchemaBridgeError.invalid(
                        keyword: "enum",
                        path: "\(path).enum[\(index)]",
                        reason: "only string enum values are supported"
                    )
                }
                return string
            }
            return .enumeration(strings)

        case "integer":
            try rejectUnexpectedKeywords(in: object, allowed: ["type"], path: path)
            return .integer

        case "number":
            try rejectUnexpectedKeywords(in: object, allowed: ["type"], path: path)
            return .number

        case "boolean":
            try rejectUnexpectedKeywords(in: object, allowed: ["type"], path: path)
            return .boolean

        case "array":
            try rejectUnexpectedKeywords(in: object, allowed: ["type", "items"], path: path)
            guard let items = object["items"] else {
                throw SchemaBridgeError.invalid(
                    keyword: "items",
                    path: path,
                    reason: "array schemas require an items schema"
                )
            }
            return .array(try parse(items, path: "\(path).items"))

        case "object":
            try rejectUnexpectedKeywords(
                in: object,
                allowed: ["type", "properties", "required", "additionalProperties"],
                path: path
            )
            if let additionalProperties = object["additionalProperties"] {
                guard let allowsAdditionalProperties = additionalProperties as? Bool,
                      !allowsAdditionalProperties else {
                    throw SchemaBridgeError.unsupported(
                        keyword: "additionalProperties",
                        path: path
                    )
                }
            }
            let rawProperties: [String: Any]
            if let properties = object["properties"] {
                guard let properties = properties as? [String: Any] else {
                    throw SchemaBridgeError.invalid(
                        keyword: "properties",
                        path: path,
                        reason: "expected an object"
                    )
                }
                rawProperties = properties
            } else {
                rawProperties = [:]
            }
            let required: Set<String>
            if let rawRequired = object["required"] {
                guard let names = rawRequired as? [String] else {
                    throw SchemaBridgeError.invalid(
                        keyword: "required",
                        path: path,
                        reason: "expected an array of property names"
                    )
                }
                required = Set(names)
            } else {
                required = []
            }
            guard required.isSubset(of: Set(rawProperties.keys)) else {
                throw SchemaBridgeError.invalid(
                    keyword: "required",
                    path: path,
                    reason: "contains a name that is not present in properties"
                )
            }
            let properties = try rawProperties.reduce(into: [String: CanonicalSchema]()) {
                result, property in
                result[property.key] = try parse(
                    property.value,
                    path: "\(path).properties.\(property.key)"
                )
            }
            return .object(properties: properties, required: required)

        default:
            throw SchemaBridgeError.invalid(
                keyword: "type",
                path: path,
                reason: "expected string, integer, number, boolean, array, or object"
            )
        }
    }

    private static func rejectUnexpectedKeywords(
        in object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        if let keyword = object.keys.filter({ !allowed.contains($0) }).sorted().first {
            throw SchemaBridgeError.unsupported(keyword: keyword, path: path)
        }
    }

    public static func generationSchema(named name: String, from value: Any) throws -> GenerationSchema {
        let canonical = try parse(value)
        let root = dynamicSchema(for: canonical, name: name)
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func dynamicSchema(
        for schema: CanonicalSchema,
        name: String
    ) -> DynamicGenerationSchema {
        switch schema {
        case .string:
            DynamicGenerationSchema(type: String.self)
        case .integer:
            DynamicGenerationSchema(type: Int.self)
        case .number:
            DynamicGenerationSchema(type: Double.self)
        case .boolean:
            DynamicGenerationSchema(type: Bool.self)
        case let .array(item):
            DynamicGenerationSchema(arrayOf: dynamicSchema(for: item, name: "\(name)_item"))
        case let .enumeration(values):
            DynamicGenerationSchema(name: name, anyOf: values)
        case let .object(properties, required):
            DynamicGenerationSchema(
                name: name,
                properties: properties.keys.sorted().map { propertyName in
                    DynamicGenerationSchema.Property(
                        name: propertyName,
                        schema: dynamicSchema(
                            for: properties[propertyName]!,
                            name: "\(name)_\(propertyName)"
                        ),
                        isOptional: !required.contains(propertyName)
                    )
                }
            )
        }
    }
}
