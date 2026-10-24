import SwiftUI
import WebKit

// MARK: - 账号编辑

struct TokenEditView: View {
    @EnvironmentObject var store: CGViewStore
    @Environment(\.dismiss) private var dismiss
    @State var token: CGToken

    var body: some View {
        NavigationStack {
            Form {
                Section("身份") {
                    TextField("标签（如：主号 / 小号）", text: $token.label)
                }
                Section {
                    SecureField("ChatGPT access token", text: $token.accessToken)
                        .font(.system(size: CG.fSmall, design: .monospaced))
                }
                Section("可选") {
                    SecureField("Team Account ID（企业版才填）", text: $token.teamAccountID)
                        .font(.system(size: CG.fSmall, design: .monospaced))
                    TextField("Device ID（留空自动生成）", text: $token.deviceID)
                        .font(.system(size: CG.fSmall, design: .monospaced))
                }
                Section {
                    Button("随机生成 Device ID") {
                        token.deviceID = UUID().uuidString
                    }
                    .font(.system(size: CG.fBody))
                    .foregroundStyle(CG.brand)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CG.bg)
            .navigationTitle("Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if token.accessToken.isEmpty { return }
                        store.addToken(token)
                        dismiss()
                    }
                    .disabled(token.accessToken.isEmpty)
                    .font(.system(size: CG.fBody, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - 浏览器登录抓取

struct TokenLoginView: View {
    @EnvironmentObject var store: CGViewStore
    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView = WKWebView()
    @State private var note = "点击「打开登录页」→ 登录你的 ChatGPT 账号 → 点「抓取 Token」"
    @State private var found: CGToken? = nil
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: CG.sp3) {
                HStack(spacing: CG.sp2) {
                    Button(action: openLogin) {
                        Label("打开登录页", systemImage: "safari.fill")
                            .font(.system(size: CG.fSmall, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(CG.brand).cornerRadius(CG.rS)
                            .foregroundStyle(.white)
                    }
                    Button(action: grab) {
                        Label(busy ? "抓取中…" : "抓取 Token", systemImage: busy ? "arrow.triangle.2.circlepath" : "hand.point.up.left")
                            .font(.system(size: CG.fSmall, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(CG.accent).cornerRadius(CG.rS)
                            .foregroundStyle(.white)
                    }
                    .disabled(busy)
                }
                Text(note)
                    .font(.system(size: CG.fCaption))
                    .foregroundStyle(CG.text2)
                    .lineSpacing(3)
                Group {
                    if let f = found {
                        TokenEditView(token: f)
                    } else {
                        WKWebViewRepresentable(webView: webView, onToken: { token in
                            self.note = "已抓到 token，请检查下方表单并保存"
                            self.found = token
                        })
                            .clipShape(RoundedRectangle(cornerRadius: CG.rM))
                            .overlay(RoundedRectangle(cornerRadius: CG.rM).stroke(CG.border, lineWidth: 0.5))
                    }
                }
            }
            .padding(CG.sp4)
            .background(CG.bg)
            .navigationTitle("浏览器登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .environment(\.colorScheme, .dark)
        }
    }

    private func openLogin() {
        note = "请登录你的 ChatGPT 账号，成功后点「抓取 Token」"
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
    }

    private func grab() {
        busy = true
        note = "正在读取会话凭证…"
        webView.evaluateJavaScript(WKNavDelegate.kickJS) { [self] result, error in
            if let s = result as? String, s != "STARTED" {
                self.note = "注入失败：\(s)"
            } else if error != nil {
                self.note = "注入失败：\(error?.localizedDescription ?? "未知错误")"
            }
            enqueuePoll(1)
        }
    }

    /// 轮询窗口变量。pollJS 所有分支都只返回字符串，不会再触发"返回类型不受支持"。
    private func poll(attempt: Int) {
        webView.evaluateJavaScript(WKNavDelegate.pollJS) { [self] result, _ in
            guard let raw = result as? String, !raw.isEmpty else {
                return enqueuePoll(attempt + 1)
            }
            let (token, diag) = WKNavDelegate.parseAll(raw)
            if let t = token {
                found = t
                note = "已获取凭证：\(t.label)　来源 \(diag)"
                busy = false
                return
            }
            if attempt >= 5 {
                note = diag
                busy = false
                return
            }
            note = "等待响应…（\(diag)）"
            enqueuePoll(attempt + 1)
        }
    }

    private func enqueuePoll(_ attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in
            self.poll(attempt: attempt)
        }
    }
}

// MARK: - WKWebView 包装

struct WKWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    var onToken: ((CGToken) -> Void)? = nil

    func makeCoordinator() -> WKNavDelegate { WKNavDelegate() }

    func makeUIView(context: Context) -> WKWebView {
        let navDelegate = context.coordinator
        webView.navigationDelegate = navDelegate
        webView.uiDelegate = navDelegate.uiDelegate
        webView.customUserAgent = CGChatGPTClient.userAgent
        webView.configuration.allowsInlineMediaPlayback = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onToken = onToken
    }
}

// 导航代理：登录完成后用 JS 同源 fetch 读 session 接口
// （accessToken 是 HttpOnly cookie，document.cookie 拿不到，
//   但同域 fetch 会自动带 cookie 并把完整 JSON 返回）
final class WKNavDelegate: NSObject, WKNavigationDelegate {
    // WKWebView.uiDelegate 是 weak，必须有人强引用，否则 delegate 立即释放
    let uiDelegate = WKCGUIDelegate()

    /// 第 1 步：发起会话请求 + 同步快照 localStorage/cookie/window，返回值永远是字符串
    static let kickJS =
        "(function(){try{" +
        "window.__CG_RES=window.__CG_RES||[];" +
        "function g(u){" +
        "try{fetch(u,{credentials:'include'}).then(function(r){" +
        "return r.text().then(function(b){" +
        "window.__CG_RES.push({u:u,s:r.status,b:String(b).slice(0,6000)})})}," +
        "function(e){window.__CG_RES.push({u:u,s:-1,e:String(e)})}).catch(function(e){" +
        "window.__CG_RES.push({u:u,s:-1,e:'CHAIN:'+String(e)})})" +
        "}catch(e){window.__CG_RES.push({u:u,s:-1,e:'THROW:'+String(e)})}}" +
        "g('/api/auth/session');" +
        "g('/api/auth/sessions');" +
        "var o={ls:{},cookie:String(document.cookie).slice(0,3000),win:{}};" +
        "try{for(var i=0;i<localStorage.length;i++){" +
        "var n=localStorage.key(i);" +
        "if(/oauth|access_token|session|account_id|chatgpt_(session|account)/i.test(n)){" +
        "var v=localStorage.getItem(n)||'';o.ls[n]=v.length>800?v.slice(0,800):v}}}catch(e){}" +
        "try{for(var k in window){" +
        "try{if(/chatgpt|oauth|access_token|session_id|account_id/i.test(k)){" +
        "var w=window[k];o.win[k]=(typeof w==='string')?w.slice(0,400):('['+typeof w+']')} }catch(e2){}}" +
        "catch(e){}" +
        "window.__CG_SNAP=JSON.stringify(o);" +
        "return 'STARTED'}catch(e){return 'KICK_ERR:'+String(e)}})()"

    /// 第 2 步：读回结果，返回值永远是字符串
    static let pollJS =
        "(function(){try{" +
        "if(!window.__CG_SNAP){return 'NOSNAP'}" +
        "var r=(window.__CG_RES||[]).map(function(x){" +
        "return x.u+'~F~'+(x.s!=null?x.s:'')+'~F~'+(x.b||x.e||'')}).join('~R~');" +
        "return JSON.stringify({snap:window.__CG_SNAP,res:r,url:String(location.href).slice(0,120)})" +
        "}catch(e){return 'POLL_ERR:'+String(e)}})()"

    var onToken: ((CGToken) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
        guard webView.url?.absoluteString.contains("chatgpt.com") == true else { return }
        // 每次落到 chatgpt.com 就提前把请求发出去，用户点「抓取 Token」时基本已就绪
        webView.evaluateJavaScript(WKNavDelegate.kickJS) { result, _ in
            _ = result
        }
    }

    /// 汇总会话接口 / localStorage / cookie / window 全局，返回 (token, 诊断)
    static func parseAll(_ raw: String) -> (CGToken?, String) {
        guard raw.hasPrefix("{") else {
            return (nil, "会话脚本未就绪：页面可能不在 chatgpt.com 或还没加载完")
        }
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, "返回内容不可解析")
        }
        let res = root["res"] as? String ?? ""
        let url = root["url"] as? String ?? ""

        let snap: [String: Any]
        if let snapRaw = root["snap"] as? String,
           let sd = snapRaw.data(using: .utf8),
           let so = try? JSONSerialization.jsonObject(with: sd) as? [String: Any] {
            snap = so
        } else {
            snap = [:]
        }

        var cands: [(String, String)] = []
        for rec in res.components(separatedBy: "~R~") {
            let p = rec.components(separatedBy: "~F~")
            if p.count >= 3, !p[2].isEmpty {
                cands.append((p[0] + " HTTP" + p[1], p[2]))
            }
        }
        if let ls = snap["ls"] as? [String: Any] {
            for k in ls.keys.sorted() { cands.append(("localStorage[\(k)]", ls[k] as? String ?? "")) }
        }
        if let ck = snap["cookie"] as? String { cands.append(("document.cookie", ck)) }
        if let win = snap["win"] as? [String: Any] {
            for k in win.keys.sorted() { cands.append(("window.\(k)", win[k] as? String ?? "")) }
        }

        // 1) 会话接口 JSON 里的 accessToken
        var tok = "", team = "", who = "", src = ""
        for (label, body) in cands {
            if !tok.isEmpty { break }
            guard let b = body.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: b) as? [String: Any] else { continue }
            if let v = o["accessToken"] as? String, !v.isEmpty {
                tok = v
                team = (o["teamAccount_id"] as? String) ?? ""
                who = (o["user"] as? String) ?? (o["username"] as? String) ?? (o["name"] as? String) ?? ""
                src = label
            }
        }

        // 2) obfuscated_oauth_token（cookie 串 / localStorage / sessionid 解一层）
        if tok.isEmpty {
            for (label, body) in cands {
                if let v = extract(body, key: "obfuscated_oauth_token"), !v.isEmpty {
                    tok = v; src = label; break
                }
            }
        }

        // 3) window.__chatgpt_session_token__
        if tok.isEmpty, let win = snap["win"] as? [String: Any],
           let v = win["__chatgpt_session_token__"] as? String, !v.isEmpty {
            tok = v
            team = (win["__chatgpt_account_id__"] as? String) ?? team
            src = "window.__chatgpt_session_token__"
        }

        guard !tok.isEmpty else {
            let loc = url.isEmpty ? "未知页面" : String(url.prefix(60))
            return (nil, "未取到 accessToken：页面=\(loc)，已扫 \(cands.count) 处候选")
        }

        var t = CGToken()
        t.accessToken = tok
        t.teamAccountID = team
        t.label = who.isEmpty ? "web-user" : who
        t.note = "浏览器登录"
        t.status = "ok"
        return (t, src)
    }

    /// 从 cookie 串或 JSON 里抠某个 key 的值（sessionid 是 URL 编码 JSON，多解一层）
    private static func extract(_ text: String, key: String) -> String? {
        if let r = text.range(of: "\(key)=") {
            let rest = text[r.upperBound...]
            let end = rest.firstIndex(where: { $0 == ";" || $0 == " " }) ?? rest.endIndex
            let v = String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        guard let data = text.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let v = o[key] as? String, !v.isEmpty { return v }
        let nested = (o["sessionid"] as? String) ?? (o["__Host-refreshToken"] as? String)
        guard let sid = nested, let dec = sid.removingPercentEncoding,
              let dd = dec.data(using: .utf8),
              let o2 = try? JSONSerialization.jsonObject(with: dd) as? [String: Any],
              let v = o2[key] as? String, !v.isEmpty else { return nil }
        return v
    }
}

// 用户代理代理：popup 目标收进当前 webview
final class WKCGUIDelegate: NSObject, WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }
}
