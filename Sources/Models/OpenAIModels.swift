import Foundation

// MARK: - OpenAI 兼容协议模型（入站）

struct OAChatRequest: Codable {
    var model: String?
    var messages: [OAMessage]
    var stream: Bool?
    var temperature: Double?
    var tools: [OATool]?
    var tool_choice: OAToolChoice?
    // 宽松解析未知字段
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try? c.decode(String?.self, forKey: .model)
        messages = (try? c.decode([OAMessage].self, forKey: .messages)) ?? []
        stream = try? c.decode(Bool?.self, forKey: .stream)
        temperature = try? c.decode(Double?.self, forKey: .temperature)
        tools = try? c.decode([OATool].self, forKey: .tools)
        tool_choice = try? c.decode(OAToolChoice.self, forKey: .tool_choice)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encode(messages, forKey: .messages)
        try c.encodeIfPresent(stream, forKey: .stream)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encodeIfPresent(tools, forKey: .tools)
        try c.encodeIfPresent(tool_choice, forKey: .tool_choice)
    }
    private enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, tools, tool_choice
    }

}

struct OAMessage: Codable {
    var role: String
    var content: JSONValue?
    var tool_calls: [OAToolCall]?
    var tool_call_id: String?
    var name: String?

    var textContent: String {
        switch content {
        case .string(let s): return s
        case .array(let parts):
            return parts.compactMap { p -> String? in
                if case .object(let o) = p, case .string(let t)? = o["text"] { return t }
                if case .string(let s) = p { return s }
                return nil
            }.joined()
        default: return ""
        }
    }
    var hasToolCalls: Bool { !(tool_calls ?? []).isEmpty }
    var isToolResult: Bool { role == "tool" || role == "function" }
}

struct OATool: Codable {
    var type: String
    var function: OAFunctionDef
}

struct OAFunctionDef: Codable {
    var name: String
    var description: String?
    var parameters: JSONValue?
}

struct OAToolChoice: Codable {
    var type: String?
    var function: OAChoiceFunction?

    private enum ChoiceKeys: String, CodingKey { case type, function }

    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            type = s
            return
        }
        let c = try decoder.container(keyedBy: ChoiceKeys.self)
        type = try? c.decode(String.self, forKey: .type)
        function = try? c.decode(OAChoiceFunction.self, forKey: .function)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ChoiceKeys.self)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(function, forKey: .function)
    }

    var forcedFunctionName: String? {
        guard type == "function" else { return nil }
        return function?.name
    }
    var isForcedNone: Bool { type == "none" }
}

struct OAChoiceFunction: Codable { var name: String }

struct OAToolCall: Codable {
    var id: String
    var type: String?
    var index: Int?
    var function: OAFunctionCall
}

struct OAFunctionCall: Codable {
    var name: String?
    var arguments: String?
}
