import Foundation

// MARK: - 工具调用引擎
// ChatGPT Web 不支持原生 tool_calls，本引擎用 `<tool_call>` 文本协议模拟：
// 注入 instructions → 模型输出标签块 → 引擎转成标准 OpenAI tool_calls。

enum CGToolCalling {

    static let openTag = "<tool_call>"
    static let closeTag = "</tool_call>"

    // MARK: 注入 instructions（system 块内容）
    static func buildInstructions(tools: [OATool], toolChoice: OAToolChoice?) -> String {
        guard !tools.isEmpty else { return "" }
        var s = ""
        s += "# YOUR ROLE: TOOL CALL TRANSLATOR\n"
        s += "You are NOT the executor of any tool. You are a tool-call translator. "
        s += "ALL tools listed below run on the USER'S OWN real machine (client-side execution). "
        s += "Your ONLY job is to convert the user's request into the correct tool call format. "
        s += "The client executes the call and returns the result to you in the next message. "
        s += "Never refuse a tool call by claiming the tool is unavailable to you — "
        s += "availability is not your concern; the client handles execution.\n"
        s += "# TOOLS AVAILABLE\n"
        s += "You have access to the following tools. Use the EXACT tool name from the list below — "
        s += "do NOT rename, abbreviate or invent names.\n\n"
        s += compactTools(tools)
        s += "\n# TOOL CALLING FORMAT (MANDATORY)\n"
        s += "To call a tool, output a JSON object wrapped EXACTLY in these tags:\n"
        s += openTag + "\n"
        s += "{\"name\": \"tool_name\", \"arguments\": {\"param_name\": \"value\"}}\n"
        s += closeTag + "\n\n"
        s += "EXAMPLE:\n"
        s += openTag + "\n"
        s += "{\"name\": \"<tool_name>\", \"arguments\": {\"arg1\": \"value1\"}}\n"
        s += closeTag + "\n\n"
        s += "CRITICAL RULES:\n"
        s += "0. Use ONLY the EXACT tool names listed under TOOLS AVAILABLE. Copy the name character-for-character.\n"
        s += "1. ONLY use the tags above for tool calling. NEVER output raw JSON without tags.\n"
        s += "2. You can call multiple tools by emitting multiple " + openTag + " blocks consecutively.\n"
        s += "3. Do NOT output any other text after your " + openTag + " blocks. Wait for the tool response.\n"
        s += "4. The JSON inside the tags MUST be valid and include the 'arguments' field.\n"
        s += "5. If you need to use a tool, do it IMMEDIATELY without preamble.\n"
        if let forced = toolChoice?.forcedFunctionName {
            s += "\nCRITICAL: You MUST call the tool \"\(forced)\" in this response. "
            s += "Do not call any other tool, and do not produce a final answer without calling it first.\n"
        } else if toolChoice?.isForcedNone == true {
            s += "\nCRITICAL: The user has DISABLED tool calling in this request. "
            s += "Do not emit any " + openTag + " blocks. Just answer in plain text.\n"
        }
        return s
    }

    // MARK: 工具清单渲染
    static func compactTools(_ tools: [OATool]) -> String {
        var s = ""
        for t in tools {
            s += "- \(t.function.name): \(t.function.description ?? "")\n"
            guard case .object(let schema)? = t.function.parameters else { continue }
            guard case .object(let props)? = schema["properties"] else { continue }
            var required: [String] = []
            if case .array(let arr)? = schema["required"] {
                required = arr.compactMap { if case .string(let x) = $0 { return x }; return nil }
            }
            s += "  Params:\n"
            for key in props.keys.sorted() {
                guard case .object(let prop) = props[key] else { continue }
                var typeStr = "string"
                if case .string(let t) = prop["type"] { typeStr = t }
                var desc = ""
                if case .string(let d) = prop["description"] { desc = d }
                let req = required.contains(key) ? "required" : "optional"
                if desc.isEmpty {
                    s += "    * \(key) (\(typeStr), \(req))\n"
                } else {
                    s += "    * \(key) (\(typeStr), \(req)): \(desc)\n"
                }
            }
        }
        return s
    }

    // MARK: 末尾提醒（tool 结果回传后追加）
    static func finalNudge(hasTools: Bool, lastRole: String) -> String {
        guard hasTools else { return "" }
        if lastRole == "tool" || lastRole == "function" {
            return "\n[SYSTEM INSTRUCTION: The 'Tool (...)' block above is the REAL output produced by "
                + "running your tool call on the user's actual machine. Treat it as ground truth. "
                + "Continue the task based strictly on it: call another tool using the exact "
                + openTag + "{...}" + closeTag + " format if you need more information, or give your final answer.]"
        }
        return "\n[SYSTEM INSTRUCTION: If you need to call a tool, do so using the exact "
            + openTag + "{...}" + closeTag + " format shown above. Otherwise just answer the user normally in plain text.]"
    }
}

// MARK: - 解析结果

struct CGToolCallParsed {
    var name: String
    var argumentsJSON: String
    var id: String
}

/// 完整文本 → (纯文本, 工具调用列表)
enum CGToolCallParser {

    static func parseComplete(_ text: String) -> (clean: String, calls: [CGToolCallParsed]) {
        var calls: [CGToolCallParsed] = []
        var clean = ""
        var rest = text
        while let open = rest.range(of: CGToolCalling.openTag),
              let close = rest.range(of: CGToolCalling.closeTag, range: open.upperBound..<rest.endIndex) {
            clean += rest[rest.startIndex..<open.lowerBound]
            let body = String(rest[open.upperBound..<close.lowerBound])
            if let call = decodeBlock(body) { calls.append(call) }
            rest = String(rest[close.upperBound...])
        }
        clean += rest
        return (clean, calls)
    }

    /// 解析单个块内容（JSON 文本）
    static func decodeBlock(_ body: String) -> CGToolCallParsed? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let name = obj["name"] as? String ?? ""
        guard !name.isEmpty else { return nil }
        var argsJSON = "{}"
        if let args = obj["arguments"] {
            if let d = try? JSONSerialization.data(withJSONObject: args),
               let s = String(data: d, encoding: .utf8) {
                argsJSON = s
            } else if let s = args as? String {
                argsJSON = s
            }
        }
        return CGToolCallParsed(name: name, argumentsJSON: argsJSON, id: "call_" + UUID().uuidString.prefix(12).lowercased())
    }
}

// MARK: - 流式解析器（增量喂文本，吐出事件）

enum CGToolStreamEvent {
    case content(String)              // 普通文本增量
    case toolCall(CGToolCallParsed)   // 完整工具块
}

final class CGToolStreamParser {
    private var buffer = ""
    private var inBlock = false
    private var blockStart = ""

    func feed(_ text: String) -> [CGToolStreamEvent] {
        var events: [CGToolStreamEvent] = []
        buffer += text
        while true {
            if inBlock {
                if let close = buffer.range(of: CGToolCalling.closeTag) {
                    let block = blockStart + String(buffer[buffer.startIndex..<close.lowerBound])
                    buffer = String(buffer[close.upperBound...])
                    inBlock = false
                    blockStart = ""
                    if let call = CGToolCallParser.decodeBlock(block) {
                        events.append(.toolCall(call))
                    }
                    continue
                }
                // 未闭合：把已确定不是标签前缀的部分固化到 blockStart
                let keep = CGToolCalling.closeTag.count + 8
                if buffer.count > keep {
                    blockStart += String(buffer.prefix(buffer.count - keep))
                    buffer = String(buffer.suffix(keep))
                }
                break
            } else {
                if let open = buffer.range(of: CGToolCalling.openTag) {
                    let before = String(buffer[buffer.startIndex..<open.lowerBound])
                    if !before.isEmpty { events.append(.content(before)) }
                    buffer = String(buffer[open.upperBound...])
                    inBlock = true
                    blockStart = ""
                    continue
                }
                // 保留可能是标签前缀的尾巴
                let keep = CGToolCalling.openTag.count - 1
                if buffer.count > keep {
                    let safe = String(buffer.prefix(buffer.count - keep))
                    events.append(.content(safe))
                    buffer = String(buffer.suffix(keep))
                }
                break
            }
        }
        return events
    }

    /// 收尾：冲刷剩余缓冲
    func flush() -> [CGToolStreamEvent] {
        var events: [CGToolStreamEvent] = []
        let rest = buffer + (inBlock ? blockStart : "")
        buffer = ""
        blockStart = ""
        inBlock = false
        if !rest.isEmpty { events.append(.content(rest)) }
        return events
    }
}

// MARK: - assistant 历史 tool_calls → 文本（供模型回顾自己调用过什么）

enum CGToolHistory {
    static func serialize(_ calls: [OAToolCall]) -> String {
        guard !calls.isEmpty else { return "" }
        var s = ""
        for c in calls {
            let name = c.function.name ?? "tool"
            let args = c.function.arguments ?? "{}"
            s += "\n" + CGToolCalling.openTag + "\n"
            s += "{\"name\": \"" + name + "\", \"arguments\": " + args + "}"
            s += "\n" + CGToolCalling.closeTag + "\n"
        }
        return s
    }
}
