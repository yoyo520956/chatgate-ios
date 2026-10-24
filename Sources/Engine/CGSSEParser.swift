
// MARK: - SSE 解析器（老格式 message + 新格式 patch）

final class CGSSEParser {
    private var fullText = ""              // 老格式累计全文
    private var patchText = ""             // 新格式累计文本
    private var usePatch = false
    private var conversationID = ""
    private var modelSlug = ""
    private var finished = false

    /// 喂一行 SSE，返回该行携带的 data 载荷（可能多个）
    func feed(line: String) -> [String] {
        var out: [String] = []
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return out }
        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return out }
        if payload == "[DONE]" { return ["[DONE]"] }
        // 兼容多个 JSON 粘连
        var rest = payload
        while let open = rest.firstIndex(of: "{"), let close = rest.lastIndex(of: "}") , open <= close {
            let chunk = String(rest[open...close])
            out.append(chunk)
            rest = String(rest[rest.index(after: close)...])
            if rest.trimmingCharacters(in: .whitespaces).isEmpty { break }
        }
        return out
    }

    /// 处理一个 JSON 载荷，返回事件（nil = 无文本增量）
    func handle(json: [String: Any]) -> CGUpstreamEvent? {
        // 新格式 patch
        if let p = json["p"] as? String {
            usePatch = true
            let op = (json["o"] as? String) ?? "append"
            let v = json["v"]
            return applyPatch(path: p, op: op, value: v)
        }
        // 老格式 message
        guard let message = json["message"] as? [String: Any] else { return nil }
        if let cid = json["conversation_id"] as? String { conversationID = cid }
        if let meta = message["metadata"] as? [String: Any] {
            if let ms = meta["model_slug"] as? String { modelSlug = ms }
        }
        var newText = ""
        if let content = message["content"] as? [String: Any],
           let parts = content["parts"] as? [String], let first = parts.first {
            newText = first
        }
        if newText.count > fullText.count {
            let delta = String(newText.suffix(newText.count - fullText.count))
            fullText = newText
            if !delta.isEmpty { return .text(delta) }
        } else if newText != fullText {
            fullText = newText
        }
        if let status = message["status"] as? String,
           status == "finished_successfully" || status == "failed" {
            finished = true
            return .done
        }
        return nil
    }

    private func applyPatch(path: String, op: String, value: Any?) -> CGUpstreamEvent? {
        if path == "/conversation_id", let v = value as? String { conversationID = v; return nil }
        if path == "/message/metadata/model_slug", let v = value as? String { modelSlug = v; return nil }
        if path == "/message/content/parts/0" {
            if op == "append", let v = value as? String {
                patchText += v
                return .text(v)
            }
            if op == "replace", let v = value as? String {
                let delta = v.hasPrefix(patchText) ? String(v.dropFirst(patchText.count)) : v
                patchText = v
                return delta.isEmpty ? nil : .text(delta)
            }
        }
        if path == "/message/content/parts", op == "replace", let arr = value as? [Any] {
            if let first = arr.first as? String {
                let delta = first.hasPrefix(patchText) ? String(first.dropFirst(patchText.count)) : first
                patchText = first
                return delta.isEmpty ? nil : .text(delta)
            }
        }
        if path == "/message/end_turn" {
            finished = true
            return .done
        }
        if path.hasPrefix("/message/metadata/finish_details") {
            finished = true
            return .done
        }
        return nil
    }

    var currentConversationID: String { conversationID }
    var currentModelSlug: String { modelSlug }
}
