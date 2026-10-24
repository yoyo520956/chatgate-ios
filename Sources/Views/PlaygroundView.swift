import SwiftUI

// MARK: - 实测页：端到端验证 tool_calls 往返

struct PlaygroundView: View {
    @EnvironmentObject var store: CGViewStore
    @State private var prompt = "现在是什么时间？请用 get_time 工具查一下，然后把结果告诉我。"
    @State private var useTools = true
    @State private var stream = true
    @State private var running = false
    @State private var result = ""
    @State private var toolCalls: [String] = []
    @State private var costMs: Int = 0
    @State private var errMsg = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CG.sp4) {
                    inputCard
                    optionsRow
                    runButton
                    resultCard
                }
                .padding(CG.sp4)
            }
            .background(CG.bg)
            .navigationTitle("实测")
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: CG.sp3) {
            Text("提问内容").font(.system(size: CG.fSmall)).foregroundStyle(CG.text2)
            TextField("输入问题", text: $prompt, axis: .vertical)
                .font(.system(size: CG.fBody))
                .lineLimit(4...8)
                .foregroundStyle(CG.text1)
                .padding(CG.sp3)
                .background(CG.bg.opacity(0.6))
                .cornerRadius(CG.rM)
                .overlay(RoundedRectangle(cornerRadius: CG.rM).stroke(CG.border, lineWidth: 0.5))
        }
        .cgCard()
    }

    private var optionsRow: some View {
        HStack(spacing: CG.sp3) {
            Toggle(isOn: $useTools) {
                Label("工具调用", systemImage: "wrench.and.screwdriver")
                    .font(.system(size: CG.fSmall))
            }
            Toggle(isOn: $stream) {
                Label("流式", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: CG.fSmall))
            }
        }
        .tint(CG.brand)
        .cgCard()
    }

    private var runButton: some View {
        Button(action: run) {
            Label(running ? "调用中…" : "发起调用",
                  systemImage: running ? "arrow.triangle.2.circlepath" : "play.fill")
                .font(.system(size: CG.fBody, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: CG.hitMin)
                .background(running ? CG.accent.opacity(0.5) : CG.brand)
                .cornerRadius(CG.rM)
                .foregroundStyle(.white)
        }
        .disabled(running)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: CG.sp3) {
            HStack {
                Text("响应").font(.system(size: CG.fSmall)).foregroundStyle(CG.text2)
                Spacer()
                if costMs > 0 {
                    Text("\(costMs) ms").font(.system(size: CG.fCaption, design: .monospaced))
                        .foregroundStyle(CG.text3).cgMono()
                }
            }
            if !errMsg.isEmpty {
                Text(errMsg).font(.system(size: CG.fSmall)).foregroundStyle(CG.danger).lineSpacing(4)
            }
            if !toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: CG.sp2) {
                    Text("工具调用 \(toolCalls.count) 次")
                        .font(.system(size: CG.fSmall, weight: .semibold))
                        .foregroundStyle(CG.ok)
                    ForEach(toolCalls, id: \.self) { s in
                        Text(s).font(.system(size: CG.fSmall, design: .monospaced))
                            .foregroundStyle(CG.text1)
                            .padding(CG.sp3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CG.ok.opacity(0.10))
                            .cornerRadius(CG.rS)
                            .lineLimit(4)
                    }
                }
            }
            if !result.isEmpty {
                Text(result).font(.system(size: CG.fBody)).foregroundStyle(CG.text1).lineSpacing(6)
                    .padding(CG.sp3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CG.bg.opacity(0.6))
                    .cornerRadius(CG.rM)
            } else if running {
                HStack(spacing: CG.sp2) {
                    Text("等待模型返回…").font(.system(size: CG.fSmall)).foregroundStyle(CG.text2)
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cgCard()
    }

    private func run() {
        guard store.isRunning else { errMsg = "网关未启动，请先在仪表盘点「启动网关」"; return }
        running = true; result = ""; toolCalls = []; errMsg = ""
        let url = URL(string: "\(store.localURL)/v1/chat/completions")!
        var body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [["role": "user", "content": prompt]],
            "stream": stream
        ]
        if useTools {
            body["tools"] = [
                [
                    "type": "function",
                    "function": [
                        "name": "get_time",
                        "description": "获取当前时间",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "timezone": ["type": "string", "description": "时区，如 Asia/Shanghai"]
                            ]
                        ]
                    ]
                ]
            ]
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if store.settings.authEnabled && !store.settings.authKey.isEmpty {
            req.setValue("Bearer " + store.settings.authKey, forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let t0 = Date()

        let session = URLSession(configuration: .ephemeral)
        Task {
            do {
                if stream {
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    if http.statusCode != 200 {
                        await MainActor.run { errMsg = "HTTP \(http.statusCode)" }
                    }
                    var acc = ""
                    var tc = ""
                    for try await line in bytes.lines {
                        let l = line.trimmingCharacters(in: .whitespaces)
                        guard l.hasPrefix("data:") else { continue }
                        let payload = String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any] else { continue }
                        if let c = delta["content"] as? String { acc += c }
                        if let tcs = delta["tool_calls"] as? [[String: Any]], let first = tcs.first {
                            tc += (first["function"] as? [String: Any])?["arguments"] as? String ?? ""
                        }
                    }
                    costMs = Int(Date().timeIntervalSince(t0) * 1000)
                    await MainActor.run {
                        result = acc
                        if useTools, !tc.isEmpty, !result.contains("工具") {
                            toolCalls = ["get_time → \(tc)"]
                        } else if useTools, tc.isEmpty {
                            toolCalls = ["（模型未返回工具调用）"]
                        }
                    }
                } else {
                    let (data, resp) = try await session.data(for: req)
                    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        let txt = String(data: data, encoding: .utf8) ?? ""
                        costMs = Int(Date().timeIntervalSince(t0) * 1000)
                        await MainActor.run { errMsg = "HTTP \(code): \(txt)"; running = false }
                        return
                    }
                    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = obj["choices"] as? [[String: Any]],
                          let msg = choices.first?["message"] as? [String: Any] else {
                        await MainActor.run { errMsg = "响应解析失败" }
                        return
                    }
                    costMs = Int(Date().timeIntervalSince(t0) * 1000)
                    await MainActor.run {
                        result = msg["content"] as? String ?? ""
                        if let tcs = msg["tool_calls"] as? [[String: Any]] {
                            for tc in tcs {
                                let fn = tc["function"] as? [String: Any]
                                toolCalls.append("\(fn?["name"] as? String ?? "?") → \(fn?["arguments"] as? String ?? "{}")")
                            }
                        } else if useTools {
                            toolCalls = ["（模型未返回工具调用）"]
                        }
                    }
                }
            } catch {
                costMs = Int(Date().timeIntervalSince(t0) * 1000)
                await MainActor.run { errMsg = error.localizedDescription }
            }
            await MainActor.run { running = false }
        }
    }
}
