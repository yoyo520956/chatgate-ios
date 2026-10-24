import Foundation

// MARK: - 网关编排层：OpenAI 兼容 ⇄ ChatGPT Web

final class CGGateway {

    // MARK: 依赖注入
    var tokenProvider: () -> [CGToken] = { [] }
    var settingsProvider: () -> CGSettings = { CGSettings() }
    var onLog: (CGRequestLog) -> Void = { _ in }
    var onToolCall: (String, String) -> Void = { _, _ in }

    private var rrIndex = 0
    private let client = CGChatGPTClient()

    // MARK: 路由
    func handle(_ req: CGHTTPRequest, _ res: CGHTTPResponder) {
        let start = Date()
        if req.method == "OPTIONS" {
            res.sendText(status: 200, text: "")
            return
        }
        let cfg = settingsProvider()
        if cfg.authEnabled && !cfg.authKey.isEmpty {
            let auth = req.header("Authorization") ?? ""
            if auth != "Bearer " + cfg.authKey {
                log(req: req, status: 401, ms: 0, error: "unauthorized", start: start)
                res.sendJSON(status: 401, data: OAErrorEnvelope.make("Invalid API key", type: "invalid_request_error", code: "invalid_api_key").jsonData())
                return
            }
        }
        switch (req.method, req.path) {
        case ("GET", "/health"), ("GET", "/"):
            let body: [String: Any] = ["status": "ok", "service": "ChatGate",
                                       "version": CGVersion.bundleShort]
            res.sendJSON(status: 200, data: (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8))
        case ("GET", "/v1/models"):
            res.sendJSON(status: 200, data: (try? JSONEncoder().encode(CGGateway.modelsResponse())) ?? Data("{}".utf8))
        case ("POST", "/v1/chat/completions"):
            handleChat(req: req, res: res, start: start)
        case ("POST", "/v1/responses"):
            handleResponses(req: req, res: res, start: start)
        default:
            res.sendJSON(status: 404, data: OAErrorEnvelope.make("Unknown path: \(req.path)", type: "invalid_request_error", code: "not_found").jsonData())
        }
    }

    // MARK: 模型列表
    static let modelIDs = [
        "gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini",
        "gpt-5", "gpt-5-mini", "chatgpt-web", "auto"
    ]

    static func modelsResponse() -> OAModelsResponse {
        let created = Int(Date().timeIntervalSince1970)
        return OAModelsResponse(data: modelIDs.map { OAModelEntry(id: $0, created: created) })
    }

    // MARK: 选 token（轮询）
    private func pickToken() -> CGToken? {
        let tokens = tokenProvider().filter { !$0.accessToken.isEmpty }
        guard !tokens.isEmpty else { return nil }
        let idx = rrIndex % tokens.count
        rrIndex += 1
        return tokens[idx]
    }

    // MARK: 记录日志
    private func log(req: CGHTTPRequest, status: Int, ms: Int, error: String, start: Date,
                     model: String = "", stream: Bool = false, tools: Bool = false, toolCount: Int = 0) {
        var entry = CGRequestLog()
        entry.method = req.method
        entry.path = req.path
        entry.model = model
        entry.stream = stream
        entry.hasTools = tools
        entry.toolCallCount = toolCount
        entry.status = status
        entry.ms = ms
        entry.client = req.header("User-Agent")?.cgTrunc40 ?? ""
        entry.error = error
        onLog(entry)
    }

    private func msSince(_ start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
}

// MARK: - 对话主流程

extension CGGateway {

    func handleChat(req: CGHTTPRequest, res: CGHTTPResponder, start: Date) {
        guard let body = req.bodyJSON,
              let data = try? JSONSerialization.data(withJSONObject: body),
              let chatReq = try? JSONDecoder().decode(OAChatRequest.self, from: data) else {
            log(req: req, status: 400, ms: msSince(start), error: "invalid json", start: start)
            res.sendJSON(status: 400, data: OAErrorEnvelope.make("Invalid request body", code: "invalid_json").jsonData())
            return
        }
        let cfg = settingsProvider()
        let modelName = chatReq.model ?? "gpt-4o"
        let wantsStream = chatReq.stream ?? false
        let hasTools = !(chatReq.tools ?? []).isEmpty

        guard let token = pickToken() else {
            log(req: req, status: 503, ms: msSince(start), error: "no token", start: start, model: modelName)
            res.sendJSON(status: 503, data: OAErrorEnvelope.make("没有可用账号 Token，请先在「账号」页添加 ChatGPT access token", type: "service_unavailable_error", code: "no_token").jsonData())
            return
        }
        var cgReq = CGChatRequest()
        cgReq.messages = chatReq.messages
        cgReq.tools = chatReq.tools ?? []
        cgReq.toolChoice = chatReq.tool_choice
        cgReq.model = cfg.modelSlug.isEmpty ? "auto" : cfg.modelSlug
        cgReq.settings = cfg

        let upstreamBody = client.buildChatGPTBody(cgReq)
        let completionID = "chatcmpl-" + UUID().uuidString.prefix(12).lowercased()
        let created = Int(Date().timeIntervalSince1970)

        Task {
            do {
                let conduit = try await client.prepare(token: token, body: upstreamBody)
                if wantsStream {
                    await streamChat(req: req, res: res, token: token, body: upstreamBody,
                                     conduit: conduit, modelName: modelName, hasTools: hasTools,
                                     start: start, completionID: completionID, created: created)
                } else {
                    await nonStreamChat(req: req, res: res, token: token, body: upstreamBody,
                                        conduit: conduit, modelName: modelName, hasTools: hasTools,
                                        start: start, completionID: completionID, created: created)
                }
            } catch {
                let msg = (error as? CGError)?.errorDescription ?? error.localizedDescription
                log(req: req, status: 502, ms: msSince(start), error: msg, start: start,
                    model: modelName, stream: wantsStream, tools: hasTools)
                if wantsStream {
                    res.beginSSE()
                    res.writeSSE("data: " + OAErrorEnvelope.make(msg, type: "upstream_error").jsonString + "\n\n")
                    res.writeSSE("data: [DONE]\n\n")
                    res.endSSE()
                } else {
                    res.sendJSON(status: 502, data: OAErrorEnvelope.make(msg, type: "upstream_error").jsonData())
                }
            }
        }
    }

    func nonStreamChat(req: CGHTTPRequest, res: CGHTTPResponder, token: CGToken,
                       body: [String: Any], conduit: String, modelName: String, hasTools: Bool,
                       start: Date, completionID: String, created: Int) async {
        var full = ""
        var toolCalls: [CGToolCallParsed] = []
        let parser = CGToolStreamParser()
        do {
            try await client.conversation(token: token, body: body, conduitToken: conduit) { ev in
                switch ev {
                case .text(let t):
                    for e in parser.feed(t) {
                        if case .content(let c) = e { full += c }
                        if case .toolCall(let call) = e { toolCalls.append(call) }
                    }
                case .done:
                    for e in parser.flush() {
                        if case .content(let c) = e { full += c }
                    }
                case .failure:
                    break
                }
            }
        } catch {
            let msg = (error as? CGError)?.errorDescription ?? error.localizedDescription
            log(req: req, status: 502, ms: msSince(start), error: msg, start: start, model: modelName, tools: hasTools)
            res.sendJSON(status: 502, data: OAErrorEnvelope.make(msg, type: "upstream_error").jsonData())
            return
        }
        var message = OAResponseMessage()
        message.content = full.isEmpty ? nil : full
        if !toolCalls.isEmpty {
            message.tool_calls = toolCalls.map { c in
                OAToolCall(id: c.id, type: "function", index: nil,
                           function: OAFunctionCall(name: c.name, arguments: c.argumentsJSON))
            }
            for c in toolCalls { onToolCall(c.name, c.argumentsJSON) }
        }
        let choice = OAChoice(index: 0, message: message,
                              finish_reason: toolCalls.isEmpty ? "stop" : "tool_calls")
        let resp = OAChatResponse(id: completionID, created: created, model: modelName,
                                  choices: [choice],
                                  usage: OAUsage(prompt_tokens: 0,
                                                 completion_tokens: estimateTokens(full),
                                                 total_tokens: estimateTokens(full)))
        res.sendJSON(status: 200, data: (try? JSONEncoder().encode(resp)) ?? Data("{}".utf8))
        log(req: req, status: 200, ms: msSince(start), error: "", start: start, model: modelName,
            tools: hasTools, toolCount: toolCalls.count)
    }

    private func estimateTokens(_ s: String) -> Int { max(1, s.count / 4) }


    // MARK: 流式
    func streamChat(req: CGHTTPRequest, res: CGHTTPResponder, token: CGToken,
                    body: [String: Any], conduit: String, modelName: String, hasTools: Bool,
                    start: Date, completionID: String, created: Int) async {
        res.beginSSE()
        let parser = CGToolStreamParser()
        var toolCount = 0
        var toolIndex = 0
        var firstChunk = true

        func emit(delta: OADelta, finish: String?) {
            let chunk = OAChunk(id: completionID, created: created, model: modelName,
                                choices: [OAChunkChoice(index: 0, delta: delta, finish_reason: finish)])
            let s = String(data: chunk.jsonData(), encoding: .utf8) ?? "{}"
            res.writeSSE("data: " + s + "\n\n")
        }

        do {
            try await client.conversation(token: token, body: body, conduitToken: conduit) { ev in
                switch ev {
                case .text(let t):
                    for e in parser.feed(t) {
                        switch e {
                        case .content(let c):
                            var d = OADelta()
                            d.content = c
                            if firstChunk { d.role = "assistant"; firstChunk = false }
                            emit(delta: d, finish: nil)
                        case .toolCall(let call):
                            toolCount += 1
                            let tc = OAToolCall(id: call.id, type: "function", index: toolIndex,
                                                function: OAFunctionCall(name: call.name, arguments: call.argumentsJSON))
                            toolIndex += 1
                            var d = OADelta()
                            d.tool_calls = [tc]
                            emit(delta: d, finish: nil)
                        }
                    }
                case .done:
                    for e in parser.flush() {
                        if case .content(let c) = e {
                            var d = OADelta()
                            d.content = c
                            emit(delta: d, finish: nil)
                        }
                    }
                case .failure:
                    break
                }
            }
            let fin = OADelta()
            emit(delta: fin, finish: toolCount > 0 ? "tool_calls" : "stop")
            res.writeSSE("data: [DONE]\n\n")
            res.endSSE()
            log(req: req, status: 200, ms: msSince(start), error: "", start: start, model: modelName,
                stream: true, tools: hasTools, toolCount: toolCount)
        } catch {
            let msg = (error as? CGError)?.errorDescription ?? error.localizedDescription
            log(req: req, status: 502, ms: msSince(start), error: msg, start: start, model: modelName, stream: true, tools: hasTools)
            res.writeSSE("data: " + OAErrorEnvelope.make(msg, type: "upstream_error").jsonString + "\n\n")
            res.writeSSE("data: [DONE]\n\n")
            res.endSSE()
        }
    }
}

// MARK: - /v1/responses（Codex 兼容）

extension CGGateway {

    func handleResponses(req: CGHTTPRequest, res: CGHTTPResponder, start: Date) {
        guard let body = req.bodyJSON,
              let data = try? JSONSerialization.data(withJSONObject: body),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            res.sendJSON(status: 400, data: OAErrorEnvelope.make("Invalid request body").jsonData())
            return
        }
        // 最小兼容：input 字符串 → 单条 user；input 数组 → 逐条转换
        var messages: [OAMessage] = []
        if let inputStr = obj["input"] as? String {
            messages = [OAMessage(role: "user", content: .string(inputStr))]
        } else if let arr = obj["input"] as? [[String: Any]] {
            for item in arr {
                let role = item["role"] as? String ?? "user"
                var text = ""
                if let c = item["content"] as? String { text = c }
                else if let parts = item["content"] as? [[String: Any]] {
                    text = parts.compactMap { $0["text"] as? String }.joined()
                }
                messages.append(OAMessage(role: role, content: .string(text)))
            }
        }
        let tools = CGGateway.parseResponseTools(obj["tools"])
        let modelName = obj["model"] as? String ?? "gpt-4o"
        guard let token = pickToken() else {
            res.sendJSON(status: 503, data: OAErrorEnvelope.make("没有可用账号 Token", type: "service_unavailable_error").jsonData())
            return
        }
        var cgReq = CGChatRequest()
        let settings = settingsProvider()
        cgReq.messages = messages
        cgReq.tools = tools
        cgReq.model = settings.modelSlug.isEmpty ? "auto" : settings.modelSlug
        cgReq.settings = settings
        let upstreamBody = client.buildChatGPTBody(cgReq)
        let respID = "resp_" + UUID().uuidString.prefix(12).lowercased()
        let created = Int(Date().timeIntervalSince1970)
        Task {
            do {
                let conduit = try await client.prepare(token: token, body: upstreamBody)
                await nonStreamOnly(res: res, token: token, body: upstreamBody, conduit: conduit,
                                    modelName: modelName, respID: respID, created: created)
            } catch {
                let msg = (error as? CGError)?.errorDescription ?? error.localizedDescription
                res.sendJSON(status: 502, data: OAErrorEnvelope.make(msg, type: "upstream_error").jsonData())
            }
        }
    }

    /// 解析 Responses API 的 tools 数组
    static func parseResponseTools(_ raw: Any?) -> [OATool] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { t in
            guard let fn = t["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return nil }
            var params: JSONValue?
            if let p = fn["parameters"] {
                if let d = try? JSONSerialization.data(withJSONObject: p),
                   let v = try? JSONDecoder().decode(JSONValue.self, from: d) {
                    params = v
                }
            }
            return OATool(type: t["type"] as? String ?? "function",
                          function: OAFunctionDef(name: name,
                                                  description: fn["description"] as? String,
                                                  parameters: params))
        }
    }

    private func nonStreamOnly(res: CGHTTPResponder, token: CGToken, body: [String: Any], conduit: String,
                               modelName: String, respID: String, created: Int) async {
        var full = ""
        var toolCalls: [CGToolCallParsed] = []
        let parser = CGToolStreamParser()
        do {
            try await client.conversation(token: token, body: body, conduitToken: conduit) { ev in
                if case .text(let t) = ev {
                    for e in parser.feed(t) {
                        if case .content(let c) = e { full += c }
                        if case .toolCall(let call) = e { toolCalls.append(call) }
                    }
                }
            }
        } catch {
            let msg = (error as? CGError)?.errorDescription ?? error.localizedDescription
            res.sendJSON(status: 502, data: OAErrorEnvelope.make(msg, type: "upstream_error").jsonData())
            return
        }
        var output: [[String: Any]] = []
        if !full.isEmpty {
            output.append(["type": "message", "role": "assistant",
                           "content": [["type": "output_text", "text": full]]])
        }
        for c in toolCalls {
            var args: Any = [:]
            if let d = c.argumentsJSON.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) { args = o }
            output.append(["type": "function_call", "call_id": c.id, "name": c.name, "arguments": args])
            onToolCall(c.name, c.argumentsJSON)
        }
        let payload: [String: Any] = [
            "id": respID, "object": "response", "created_at": created,
            "model": modelName, "status": "completed",
            "output": output,
            "output_text": full,
            "usage": ["input_tokens": 0, "output_tokens": estimateTokens(full), "total_tokens": estimateTokens(full)]
        ]
        res.sendJSON(status: 200, data: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8))
    }
}

// MARK: - 版本信息

enum CGVersion {
    static var bundleShort: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    static var bundleBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
