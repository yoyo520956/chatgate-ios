import Foundation
import SwiftUI
import Combine
import Network

// MARK: - 全局状态中心

final class CGViewStore: ObservableObject {
    static let shared = CGViewStore()

    @Published var tokens: [CGToken] = []
    @Published var settings: CGSettings = CGSettings()
    @Published var logs: [CGRequestLog] = []
    @Published var stats: CGStats = CGStats()
    @Published var isRunning = false
    @Published var runningPort: Int = 0
    @Published var serverMessage = "未启动"
    @Published var busyTokenID: UUID? = nil

    private var server: CGHTTPServer?
    private let gateway = CGGateway()

    init() {
        let snap = CGStore.load()
        tokens = snap.tokens
        settings = snap.settings
        logs = snap.logs
        stats = snap.stats
        stats.startedAt = stats.startedAt ?? Date()
        gateway.tokenProvider = { [weak self] in self?.tokens ?? [] }
        gateway.settingsProvider = { [weak self] in self?.settings ?? CGSettings() }
        gateway.onLog = { [weak self] in self?.appendLog($0) }
        gateway.onToolCall = { [weak self] _, _ in self?.addToolCall() }
    }

    // MARK: 服务器生命周期
    func start() {
        guard !isRunning else { return }
        let srv = CGHTTPServer()
        srv.onRequest = { [weak self] req, res in self?.gateway.handle(req, res) }
        srv.onStateChange = { [weak self] running, message in
            DispatchQueue.main.async {
                self?.isRunning = running
                self?.runningPort = srv.listeningPort > 0 ? srv.listeningPort : (running ? self?.settings.port ?? 0 : 0)
                self?.serverMessage = message
            }
        }
        srv.start(port: settings.port)
        server = srv
        if settings.keepAwake { CGKeepAlive.start() }
        DispatchQueue.main.async {
            self.isRunning = true
            self.runningPort = srv.listeningPort > 0 ? srv.listeningPort : self.settings.port
        }
    }

    func stop() {
        server?.stop()
        server = nil
        if !settings.keepAwake { CGKeepAlive.stop() }
        isRunning = false
        runningPort = 0
        serverMessage = "已停止"
    }

    func toggle() { isRunning ? stop() : start() }

    // MARK: Token 管理
    func addToken(_ t: CGToken) {
        tokens.append(t)
        save()
    }

    func updateToken(_ t: CGToken) {
        guard let i = tokens.firstIndex(where: { $0.id == t.id }) else { return }
        tokens[i] = t
        save()
    }

    func removeToken(id: UUID) {
        tokens.removeAll { $0.id == id }
        save()
    }

    // MARK: 统计
    private func appendLog(_ e: CGRequestLog) {
        DispatchQueue.main.async {
            self.logs.insert(e, at: 0)
            if self.logs.count > 300 { self.logs = Array(self.logs.prefix(300)) }
            if e.status >= 400 { self.stats.totalErrors += 1 }
            self.save()
        }
    }

    private func addToolCall() {
        DispatchQueue.main.async { self.stats.totalToolCalls += 1 }
    }

    func clearLogs() {
        logs.removeAll()
        save()
    }

    func resetStats() {
        stats = CGStats()
        stats.startedAt = Date()
        save()
    }

    // MARK: 持久化
    func save() {
        CGStore.save(CGStore.Snapshot(tokens: tokens, settings: settings, logs: logs, stats: stats))
    }

    // MARK: 端点信息
    var localURL: String { "http://127.0.0.1:\(runningPort)" }

    var lanIP: String {
        var address = ""
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "0.0.0.0" }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let family = cur.pointee.ifa_addr.pointee.sa_family
            if flags & IFF_UP == IFF_UP,
               flags & IFF_LOOPBACK == 0,
               family == UInt8(AF_INET) {
                let name = String(cString: cur.pointee.ifa_name)
                if name == "en0" || name.hasPrefix("en") {
                    var host = [Int8](repeating: 0, count: Int(NI_MAXHOST))
                    let rc = host.withUnsafeMutableBufferPointer { ptr in
                        getnameinfo(cur.pointee.ifa_addr,
                                    socklen_t(cur.pointee.ifa_addr.pointee.sa_len),
                                    ptr.baseAddress, socklen_t(NI_MAXHOST),
                                    nil, 0, NI_NUMERICHOST)
                    }
                    if rc == 0 {
                        address = String(cString: host)
                        break
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return address.isEmpty ? "0.0.0.0" : address
    }

    var lanURL: String { "http://\(lanIP):\(runningPort)" }

    var endpointLine: String {
        guard isRunning && runningPort > 0 else { return "— 服务未启动 —" }
        return localURL
    }
}
