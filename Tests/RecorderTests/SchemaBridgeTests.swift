import Foundation
import Testing
@testable import Recorder

// REQ: agent-loop-implementation.md §6 — migrated from Experiments/FoundationModelsPOC.

@Test("Representative MCP object schema converts to Apple's GenerationSchema")
func schemaBridgeBuildsGenerationSchema() throws {
    let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "path": ["type": "string"],
            "mode": ["type": "string", "enum": ["brief", "full"]],
            "limit": ["type": "integer"],
        ],
        "required": ["path"],
    ]
    let generationSchema = try SchemaBridge.generationSchema(named: "ReadFixture", from: schema)
    let encoded = try JSONEncoder().encode(generationSchema)
    #expect(!encoded.isEmpty)
}

@Test("Lossy schema keywords and mixed enums fail with their exact path")
func schemaBridgeRejectsLossySchemas() {
    #expect(throws: SchemaBridgeError.unsupported(keyword: "anyOf", path: "$.properties.mode")) {
        try SchemaBridge.parse(["anyOf": []], path: "$.properties.mode")
    }
    #expect(throws: SchemaBridgeError.invalid(
        keyword: "enum", path: "$.enum[1]", reason: "only string enum values are supported"
    )) {
        try SchemaBridge.parse(["type": "string", "enum": ["one", 2]])
    }
    #expect(throws: SchemaBridgeError.unsupported(keyword: "description", path: "$")) {
        try SchemaBridge.parse(["type": "string", "description": "Must not be discarded"])
    }
    #expect(throws: SchemaBridgeError.unsupported(keyword: "enum", path: "$")) {
        try SchemaBridge.parse(["type": "integer", "enum": [1, 2]])
    }
    #expect(throws: SchemaBridgeError.unsupported(keyword: "items", path: "$")) {
        try SchemaBridge.parse(["type": "boolean", "items": ["type": "string"]])
    }
}
