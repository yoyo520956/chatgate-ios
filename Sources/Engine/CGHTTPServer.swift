import Foundation
import Network

// MARK: - 入站 HTTP 请求

struct CGHTTPRequest {
    var method: String = "GET"
    var path: String = "/"
    var query: [String: String] = [:]
    var headers: [String: String] = [:]
    var body: Data = Data()
    var clientIP: String = ""

    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
    var bodyText: String { String(data: body, encoding: .utf8) ?? "" }
    var bodyJSON: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

// MARK: - 响应写入器（支持 JSON 与 SSE 流）

final class CGHTTPResponder {
    private let conn: NWConnection
    private let queue: DispatchQueue
    private var headersSent = false
    private var finished = false

    init(conn: NWConnection, queue: DispatchQueue) {
        self.conn = conn
        self.queue = queue
    }

    private func sendHeader(status: Int, contentType: String, extra: [String: String] = [:]) {
        guard !headersSent else { return }
        headersSent = true
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: *\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, OPTIONS, DELETE\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Connection: close\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
    }

    func sendJSON(status: Int, data: Data) {
        queue.async {
            guard !self.finished else { return }
            self.finished = true
            self.sendHeader(status: status, contentType: "application/json; charset=utf-8",
                            extra: ["Content-Length": "\(data.count)"])
            self.conn.send(content: data, completion: .contentProcessed { _ in
                self.conn.cancel()
            })
        }
    }

    func sendText(status: Int, text: String) {
        sendJSON(status: status, data: Data(text.utf8))
    }

    /// 开始 SSE 流
    func beginSSE() {
        queue.async {
            guard !self.headersSent, !self.finished else { return }
            self.headersSent = true
            var head = "HTTP/1.1 200 OK\r\n"
            head += "Content-Type: text/event-stream; charset=utf-8\r\n"
            head += "Cache-Control: no-cache\r\n"
            head += "Connection: close\r\n"
            head += "Access-Control-Allow-Origin: *\r\n"
            head += "Transfer-Encoding: chunked\r\n\r\n"
            self.conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        }
    }

    /// 写一条 SSE 事件（chunked 编码）
    func writeSSE(_ payload: String) {
        queue.async {
            guard !self.finished else { return }
            let data = Data(payload.utf8)
            let hex = String(data.count, radix: 16)
            var chunk = Data(hex.utf8)
            chunk.append(Data("\r\n".utf8))
            chunk.append(data)
            chunk.append(Data("\r\n".utf8))
            self.conn.send(content: chunk, completion: .contentProcessed { _ in })
        }
    }

    func endSSE() {
        queue.async {
            guard !self.finished else { return }
            self.finished = true
            let tail = Data("0\r\n\r\n".utf8)
            self.conn.send(content: tail, completion: .contentProcessed { _ in
                self.conn.cancel()
            })
        }
    }

    func abort() {
        queue.async {
            self.finished = true
            self.conn.cancel()
        }
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }
}

// MARK: - 服务器主体

final class CGHTTPServer {
    typealias Handler = (CGHTTPRequest, CGHTTPResponder) -> Void

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "cg.http.server", attributes: .concurrent)
    private(set) var listeningPort: Int = 0
    private(set) var isRunning = false
    var onRequest: Handler?
    var onStateChange: ((Bool, String) -> Void)?

    func start(port: Int) {
        stop()
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // NWListener(using:on:) 有两个重载（on: NWEndpoint / on: NWEndpoint.Port），
            // 传 hostPort 结果会命中 Port 重载而报类型错；直接传 Port 无歧义，
            // 且 Port 重载默认绑定全部网卡（等价 0.0.0.0），正合本机网关需求。
            let portNum = NWEndpoint.Port(rawValue: UInt16(port))!
            let l = try NWListener(using: params, on: portNum)
            listener = l
            l.stateUpdateHandler = { [weak self] (state: NWListener.State) in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.listeningPort = Int(l.port?.rawValue ?? UInt16(port))
                    self.isRunning = true
                    self.onStateChange?(true, "监听端口 \(self.listeningPort)")
                case .failed(let err):
                    self.isRunning = false
                    self.onStateChange?(false, "监听失败：\(err.localizedDescription)")
                case .cancelled:
                    self.isRunning = false
                    self.onStateChange?(false, "已停止")
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.start(queue: queue)
        } catch {
            isRunning = false
            onStateChange?(false, "启动异常：\(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: 连接处理
    private func handle(_ conn: NWConnection) {
        conn.stateUpdateHandler = { state in
            if case .failed = state { conn.cancel() }
        }
        conn.start(queue: queue)
        receive(conn: conn, buffer: Data())
    }

    private func receive(conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if error != nil { conn.cancel(); return }

            if let req = self.parse(buf) {
                let responder = CGHTTPResponder(conn: conn, queue: self.queue)
                self.onRequest?(req, responder)
                return
            }
            if isComplete { conn.cancel(); return }
            self.receive(conn: conn, buffer: buf)
        }
    }

    // MARK: HTTP 解析
    private func parse(_ data: Data) -> CGHTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[data.startIndex..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ", maxSplits: 2).map(String.init)
        guard requestLine.count >= 2 else { return nil }

        var req = CGHTTPRequest()
        req.method = requestLine[0]
        let fullPath = requestLine[1]
        if let qIdx = fullPath.firstIndex(of: "?") {
            req.path = String(fullPath[fullPath.startIndex..<qIdx])
            let queryStr = String(fullPath[fullPath.index(after: qIdx)...])
            for pair in queryStr.components(separatedBy: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 {
                    req.query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        } else {
            req.path = fullPath
        }
        for line in lines {
            guard let sep = line.firstIndex(of: ":") else { continue }
            let k = String(line[line.startIndex..<sep]).trimmingCharacters(in: .whitespaces)
            let v = String(line[line.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
            req.headers[k] = v
        }

        let contentLength = Int(req.header("Content-Length") ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        let available = data.count - bodyStart
        if available < contentLength { return nil }
        req.body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return req
    }
}
