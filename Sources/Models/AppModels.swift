import Foundation

// MARK: - App 数据模型（Token / 设置 / 日志 / 统计）

struct CGToken: Codable, Identifiable {
    var id: UUID = UUID()
    var label: String = ""
    var accessToken: String = ""
    var teamAccountID: String = ""      // 可选 ChatGPT-Account-Id
    var deviceID: String = ""           // oai-device-id（稳定指纹）
    var sessionID: String = ""          // oai-session-id
    var addedAt: Date = Date()
    var lastCheckedAt: Date?
    var status: String = "unknown"      // ok | invalid | unknown
    var note: String = ""

    var masked: String {
        let t = accessToken
        guard t.count > 14 else { return String(repeating: "•", count: t.count) }
        return String(t.prefix(8)) + "…" + String(t.suffix(6))
    }
}

struct CGSettings: Codable, Equatable {
    var port: Int = 8688
    var authEnabled: Bool = false        // 开启访问鉴权
    var authKey: String = ""             // 鉴权密钥
    var proxyURL: String = ""            // http://ip:port 可选
    var historyDisabled: Bool = true     // 不保存聊天记录
    var thinkingEffort: String = "standard" // standard | extended | max
    var keepAwake: Bool = false          // 静音音频后台保活
    var retryTimes: Int = 2
    var modelSlug: String = "auto"

    static func randomKey() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let s = (0..<24).map { _ in chars.randomElement()! }
        return "cg-" + String(s)
    }
}

struct CGRequestLog: Codable, Identifiable {
    var id = UUID()
    var at: Date = Date()
    var method: String = "POST"
    var path: String = "/v1/chat/completions"
    var model: String = ""
    var stream: Bool = false
    var hasTools: Bool = false
    var toolCallCount: Int = 0
    var status: Int = 200
    var ms: Int = 0
    var client: String = ""
    var error: String = ""
}

struct CGStats: Codable {
    var totalRequests: Int = 0
    var totalToolCalls: Int = 0
    var totalErrors: Int = 0
    var startedAt: Date?
}

// MARK: - 状态持久化

enum CGStore {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("chatgate_state.json")
    }

    struct Snapshot: Codable {
        var tokens: [CGToken] = []
        var settings: CGSettings = CGSettings()
        var logs: [CGRequestLog] = []
        var stats: CGStats = CGStats()
    }

    static func load() -> Snapshot {
        guard let d = try? Data(contentsOf: fileURL) else { return Snapshot() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Snapshot.self, from: d)) ?? Snapshot()
    }

    static func save(_ s: Snapshot) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(s) {
            try? d.write(to: fileURL, options: .atomic)
        }
    }
}
