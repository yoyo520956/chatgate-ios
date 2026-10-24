import Foundation

// MARK: - 宽松 JSON 值（兼容任意 schema）

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil().self { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported json")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var jsonString: String {
        guard let d = try? JSONEncoder().encode(self) else { return "null" }
        return String(data: d, encoding: .utf8) ?? "null"
    }
}

// MARK: - OpenAI 出站响应模型

struct OAChatResponse: Codable {
    var id: String
    var object: String = "chat.completion"
    var created: Int
    var model: String
    var choices: [OAChoice]
    var usage: OAUsage?
}

struct OAChoice: Codable {
    var index: Int = 0
    var message: OAResponseMessage
    var finish_reason: String?
}

struct OAResponseMessage: Codable {
    var role: String = "assistant"
    var content: String?
    var tool_calls: [OAToolCall]?
}

struct OAUsage: Codable {
    var prompt_tokens: Int
    var completion_tokens: Int
    var total_tokens: Int
}

// MARK: - 流式 chunk

struct OAChunk: Codable {
    var id: String
    var object: String = "chat.completion.chunk"
    var created: Int
    var model: String
    var choices: [OAChunkChoice]
    var usage: OAUsage?

    func jsonData() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data("{}".utf8)
    }
}

struct OAChunkChoice: Codable {
    var index: Int = 0
    var delta: OADelta
    var finish_reason: String?
}

struct OADelta: Codable {
    var role: String?
    var content: String?
    var tool_calls: [OAToolCall]?
}

// MARK: - /v1/models 响应

struct OAModelsResponse: Codable {
    var object: String = "list"
    var data: [OAModelEntry]
}

struct OAModelEntry: Codable {
    var id: String
    var object: String = "model"
    var created: Int
    var owned_by: String = "chatgate"
}

// MARK: - 错误响应

struct OAErrorEnvelope: Codable {
    struct OAError: Codable {
        var message: String
        var type: String
        var code: String?
    }
    var error: OAError

    static func make(_ msg: String, type: String = "invalid_request_error", code: String? = nil) -> OAErrorEnvelope {
        OAErrorEnvelope(error: .init(message: msg, type: type, code: code))
    }
    func jsonData() -> Data { (try? JSONEncoder().encode(self)) ?? Data("{}".utf8) }
    var jsonString: String { String(data: jsonData(), encoding: .utf8) ?? "{}" }
}
