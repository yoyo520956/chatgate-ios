import Foundation

// MARK: - 上游事件

enum CGUpstreamEvent {
    case text(String)
    case done
    case failure(String)
}

// MARK: - 客户端入参

struct CGChatRequest {
    var messages: [OAMessage] = []
    var tools: [OATool] = []
    var toolChoice: OAToolChoice?
    var model: String = "auto"
    var stream: Bool = false
    var settings: CGSettings = CGSettings()
}

// MARK: - ChatGPT Web 协议客户端

final class CGChatGPTClient {

    static let baseURL = "https://chatgpt.com/backend-api"
    static let anonBaseURL = "https://chatgpt.com/backend-anon"
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"

    private let session: URLSession

    init(proxyURL: String = "") {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        cfg.httpShouldSetCookies = false
        cfg.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9"]
        if let p = CGChatGPTClient.parseProxy(proxyURL) {
            cfg.connectionProxyDictionary = [
                "HTTPEnable": true, "HTTPProxyHost": p.host, "HTTPPort": p.port,
                "HTTPSEnable": true, "HTTPSProxyHost": p.host, "HTTPSProxyPort": p.port
            ]
        }
        session = URLSession(configuration: cfg)
    }

    static func parseProxy(_ raw: String) -> (host: String, port: Int)? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var body = s
        if body.hasPrefix("http://") { body = String(body.dropFirst(7)) }
        else if body.hasPrefix("https://") { body = String(body.dropFirst(8)) }
        let parts = body.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = parts.first, !host.isEmpty else { return nil }
        let port = parts.count > 1 ? Int(parts[1]) ?? 7890 : 7890
        return (host, port)
    }

    // MARK: 基础 headers
    func baseHeaders(token: CGToken, conversationID: String = "") -> [String: String] {
        var h: [String: String] = [:]
        h["Accept"] = "*/*"
        h["Accept-Language"] = "en-US,en;q=0.9"
        h["Oai-Language"] = "en-US"
        h["Origin"] = "https://chatgpt.com"
        h["Referer"] = conversationID.isEmpty ? "https://chatgpt.com/" : "https://chatgpt.com/c/\(conversationID)"
        h["Sec-Ch-Ua"] = "\"Chromium\";v=\"150\", \"Google Chrome\";v=\"150\", \"Not/A)Brand\";v=\"99\""
        h["Sec-Ch-Ua-Mobile"] = "?0"
        h["Sec-Ch-Ua-Platform"] = "\"Windows\""
        h["Priority"] = "u=1, i"
        h["Sec-Fetch-Dest"] = "empty"
        h["Sec-Fetch-Mode"] = "cors"
        h["Sec-Fetch-Site"] = "same-origin"
        h["User-Agent"] = CGChatGPTClient.userAgent
        h["Oai-Client-Build-Number"] = "7823760"
        h["Oai-Client-Version"] = "7823760"
        h["Oai-Device-Id"] = token.deviceID.isEmpty ? UUID().uuidString : token.deviceID
        h["Oai-Session-Id"] = token.sessionID.isEmpty ? UUID().uuidString : token.sessionID
        if !token.accessToken.isEmpty {
            h["Authorization"] = "Bearer \(token.accessToken)"
        }
        if !token.teamAccountID.isEmpty {
            h["Chatgpt-Account-Id"] = token.teamAccountID
        }
        return h
    }

    // MARK: OpenAI 消息 → ChatGPT 消息体
    func buildChatGPTBody(_ req: CGChatRequest) -> [String: Any] {
        var messages: [[String: Any]] = []
        var systemParts: [String] = []

        for m in req.messages where m.role == "system" {
            let t = m.textContent
            if !t.isEmpty { systemParts.append(t) }
        }
        let hasTools = !req.tools.isEmpty
        if hasTools {
            let block = CGToolCalling.buildInstructions(tools: req.tools, toolChoice: req.toolChoice)
            systemParts.append("<tool_calling_protocol>\n" + block + "\n</tool_calling_protocol>")
        }
        if !systemParts.isEmpty {
            messages.append([
                "id": UUID().uuidString,
                "author": ["role": "system"],
                "create_time": Self.nowSeconds(),
                "content": ["content_type": "text", "parts": [systemParts.joined(separator: "\n\n")]],
                "metadata": Self.defaultMetadata()
            ])
        }

        var lastRole = ""
        for m in req.messages {
            if m.role == "system" { continue }
            lastRole = m.role
            if m.isToolResult {
                let name = m.name ?? "tool"
                let text = "[tool result of \(name)]:\n" + m.textContent
                messages.append(Self.msg(role: "user", text: text))
                continue
            }
            var text = m.textContent
            if m.role == "assistant" && m.hasToolCalls {
                text += CGToolHistory.serialize(m.tool_calls ?? [])
            }
            if m.role == "assistant" && hasTools {
                text += CGToolCalling.finalNudge(hasTools: true, lastRole: "assistant")
            }
            messages.append(Self.msg(role: m.role, text: text))
        }
        if hasTools {
            // 最后一条 user 消息后追加温和提醒
            if lastRole == "user", var last = messages.last {
                let nudge = CGToolCalling.finalNudge(hasTools: true, lastRole: "user")
                if let content = last["content"] as? [String: Any],
                   let parts = content["parts"] as? [Any],
                   let p = parts.first as? String {
                    var newParts = parts
                    newParts[0] = p + nudge
                    last["content"] = ["content_type": "text", "parts": newParts]
                    messages[messages.count - 1] = last
                }
            }
        }

        let body: [String: Any] = [
            "action": "next",
            "messages": messages,
            "parent_message_id": "client-created-root",
            "model": req.model.isEmpty ? "auto" : req.model,
            "history_and_training_disabled": req.settings.historyDisabled,
            "timezone_offset_min": -480,
            "timezone": "America/Los_Angeles",
            "conversation_mode": ["kind": "primary_assistant"],
            "system_hints": [],
            "paragen_cot_summary_display_override": "allow",
            "force_parallel_switch": "auto",
            "thinking_effort": req.settings.thinkingEffort
        ]
        return body
    }

    static func msg(role: String, text: String) -> [String: Any] {
        [
            "id": UUID().uuidString,
            "author": ["role": role],
            "create_time": nowSeconds(),
            "content": ["content_type": "text", "parts": [text]],
            "metadata": defaultMetadata()
        ]
    }

    static func defaultMetadata() -> [String: Any] {
        [
            "developer_mode_connector_ids": [Any](),
            "selected_sources": [Any](),
            "selected_github_repos": [Any](),
            "selected_all_github_repos": false,
            "serialization_metadata": ["custom_symbol_offsets": [Any]()]
        ]
    }

    static func nowSeconds() -> Double { Date().timeIntervalSince1970 }

    // MARK: - prepare：取 conduit_token
    func prepare(token: CGToken, body: [String: Any]) async throws -> String {
        let target = "/backend-api/f/conversation/prepare"
        var payload = body
        payload["client_prepare_state"] = "none"
        payload["client_prepare_dispatch"] = "debounced"
        payload["client_prepare_source"] = "composer_editor_state"
        payload["supports_buffering"] = true
        payload["supported_encodings"] = ["v1"]
        payload["client_contextual_info"] = ["app_name": "chatgpt.com"]
        payload["local_function_names"] = ["local.continue_in_work"]
        payload["partial_query"] = [
            "id": UUID().uuidString,
            "author": ["role": "user"],
            "content": ["content_type": "text", "parts": [partialText(body)]]
        ]

        var headers = baseHeaders(token: token)
        headers["Content-Type"] = "application/json"
        headers["X-Openai-Target-Path"] = target
        headers["X-Openai-Target-Route"] = target
        headers["X-Oai-Turn-Trace-Id"] = UUID().uuidString

        var req = URLRequest(url: URL(string: Self.baseURL + "/f/conversation/prepare")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CGError.badResponse }
        guard http.statusCode == 200 else {
            throw CGError.upstream("prepare HTTP \(http.statusCode): " + (String(data: data, encoding: .utf8) ?? "").cgTrunc40)
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let token2 = obj?["conduit_token"] as? String, !token2.isEmpty else {
            throw CGError.upstream("prepare 未返回 conduit_token")
        }
        return token2
    }

    private func partialText(_ body: [String: Any]) -> String {
        guard let msgs = body["messages"] as? [[String: Any]] else { return "h" }
        for m in msgs.reversed() {
            guard let author = m["author"] as? [String: Any], author["role"] as? String == "user" else { continue }
            if let content = m["content"] as? [String: Any], let parts = content["parts"] as? [String], let first = parts.first {
                let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return String(t.prefix(5)) }
            }
        }
        return "h"
    }

    // MARK: - conversation：SSE 流式对话
    func conversation(token: CGToken, body: [String: Any], conduitToken: String,
                      onEvent: @escaping @Sendable (CGUpstreamEvent) -> Void) async throws {
        let target = "/backend-api/f/conversation"
        var headers = baseHeaders(token: token)
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "text/event-stream"
        headers["X-Openai-Target-Path"] = target
        headers["X-Openai-Target-Route"] = target
        headers["X-Conduit-Token"] = conduitToken
        headers["X-Oai-Turn-Trace-Id"] = UUID().uuidString
        headers["Oai-Echo-Logs"] = "0,943,1,65876,0,68124,1,68930"
        headers["Oai-Telemetry"] = "[1,null]"
        if !token.deviceID.isEmpty {
            headers["Cookie"] = "oai-did=\(token.deviceID)"
        }

        var req = URLRequest(url: URL(string: Self.baseURL + "/f/conversation")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw CGError.badResponse }
        guard http.statusCode == 200 else {
            var collected = ""
            do {
                for try await line in bytes.lines {
                    collected += line + "\n"
                    if collected.utf8.count > 300 { break }
                }
            } catch {}
            throw CGError.upstream("conversation HTTP \(http.statusCode): " + collected.cgTrunc40)
        }

        let parser = CGSSEParser()
        for try await line in bytes.lines {
            for payload in parser.feed(line: line) {
                if payload == "[DONE]" {
                    onEvent(.done)
                    return
                }
                guard let data = payload.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let ev = parser.handle(json: obj) {
                    onEvent(ev)
                    if case .done = ev { return }
                }
            }
        }
        onEvent(.done)
    }
}

// MARK: - 错误

enum CGError: LocalizedError {
    case badResponse
    case upstream(String)
    case noToken
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "无效的网络响应"
        case .upstream(let m): return m
        case .noToken: return "没有可用的 ChatGPT 账号 Token，请先在「账号」页添加"
        case .unauthorized(let m): return m
        }
    }
}
