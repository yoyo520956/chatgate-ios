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
    @State private var note = "点「打开登录页」→ 在页面里登录 → 状态会自动更新，登录成功后点「抓取 Token」"
    @State private var live = ""
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
                if !live.isEmpty {
                    HStack(spacing: CG.sp1) {
                        Circle()
                            .fill(liveColor)
                            .frame(width: 7, height: 7)
                        Text(live)
                            .font(.system(size: CG.fCaption, weight: .medium))
                            .foregroundStyle(CG.text2)
                            .lineLimit(2)
                    }
                }
                Text(note)
                    .font(.system(size: CG.fCaption))
                    .foregroundStyle(CG.text2)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let f = found {
                        TokenEditView(token: f)
                    } else {
                        WKWebViewRepresentable(webView: webView, onToken: { token in
                            self.note = "已抓到 token，请检查下方表单并保存"
                            self.found = token
                        }, onLive: { text in
                            self.live = text
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

    private var liveColor: Color {
        if live.hasPrefix("已登录") { return CG.ok }
        if live.hasPrefix("未登录") { return CG.warn }
        return CG.accent
    }

    private func openLogin() {
        note = "请登录你的 ChatGPT 账号，页面加载后状态会自动更新"
        live = "页面加载中…"
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
    }

    /// 手动抓取：连发多轮探测。每一轮都自己重新发请求 + 重新快照，
    /// 所以中间发生页面重新导航（登录流程几乎必然）也不会丢状态。
    private func grab() {
        busy = true
        note = "正在探测会话凭证…"
        runProbe(1)
    }

    private func runProbe(_ attempt: Int) {
        webView.evaluateJavaScript(WKNavDelegate.probeJS) { [self] result, error in
            if let raw = result as? String, !raw.isEmpty {
                let r = WKNavDelegate.parseProbe(raw)
                if !r.live.isEmpty { live = r.live }
                note = r.msg
                if let t = r.token {
                    found = t
                    busy = false
                    return
                }
                if attempt >= 6 { busy = false; return }
                return scheduleProbe(attempt + 1)
            }
            // evaluateJavaScript 本身失败：页面未就绪 / JS 被挂起
            let e = error.map { String($0.localizedDescription) } ?? "unknown"
            live = "页面未就绪"
            note = "脚本没能执行：" + e
            if attempt >= 6 { busy = false; return }
            return scheduleProbe(attempt + 1)
        }
    }

    private func scheduleProbe(_ attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in
            runProbe(attempt)
        }
    }
}

// MARK: - WKWebView 包装

struct WKWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    var onToken: ((CGToken) -> Void)? = nil
    var onLive: ((String) -> Void)? = nil

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
        context.coordinator.onLive = onLive
    }
}

// 导航代理：登录完成后用 JS 同源 fetch 读 session 接口
// （accessToken 是 HttpOnly cookie，document.cookie 拿不到，
//   但同域 fetch 会自动带 cookie 并把完整 JSON 返回）
final class WKNavDelegate: NSObject, WKNavigationDelegate {
    // WKWebView.uiDelegate 是 weak，必须有人强引用，否则 delegate 立即释放
    let uiDelegate = WKCGUIDelegate()

    /// 单次自愈探测：
    /// 1) 没发过的 session 请求才发（失败会自动清标记，下一轮重试）
    /// 2) 每次都重新快照 localStorage / cookie / window 全局
    /// 3) 永远返回一个 JSON 字符串；URL 和 readyState 无条件在结果里
    /// 4) 所有分支都返回字符串，绝不返回 Promise / undefined / null / number / boolean
    ///    —— WKWebView.evaluateJavaScript 只接受 JS 对象和 JS 字符串
    static let probeJS =
        "(function(){" +
        "try{" +
        "var W=window;" +
        "if(!W.__CG_P){W.__CG_P={f:{},done:0}}" +
        "var P=W.__CG_P;" +
        "function fire(u){" +
        "if(P.f[u]){return}" +
        "P.f[u]=1;" +
        "var rec={u:u,s:0,b:'',e:''};" +
        "var put=function(){" +
        "if(!W.__CG_RES){W.__CG_RES=[]}" +
        "W.__CG_RES.push(rec)" +
        "};" +
        "var drop=function(){delete P.f[u]};" +
        "try{" +
        "if(typeof fetch!=='function'){rec.e='NO_FETCH';put();drop();return}" +
        "fetch(u,{credentials:'include'}).then(function(r){" +
        "rec.s=r.status;" +
        "try{var ct=r.headers?r.headers.get('content-type'):'';rec.t=ct}catch(e3){}" +
        "return r.text().then(function(b){" +
        "rec.b=String(b).slice(0,2500);put()}" +
        ",function(e4){rec.e='BODY:'+String(e4);put();drop()})" +
        "},function(e){" +
        "rec.e='REJ:'+String(e);put();drop()" +
        "}).catch(function(e5){" +
        "if(!rec.e){rec.e='CHAIN:'+String(e5)}" +
        "put();drop()" +
        "})" +
        "}catch(e2){rec.e='THROW:'+String(e2);put();drop()}" +
        "}" +
        "if(!P.done){['/api/auth/session','/api/auth/sessions'].forEach(fire);P.done=1}" +
        "var o={ls:{},win:{}};" +
        "try{for(var i=0;i<localStorage.length;i++){" +
        "var n=localStorage.key(i);" +
        "if(/oauth|access_token|session|account|chatgpt/i.test(n)){" +
        "var v=localStorage.getItem(n)||'';" +
        "o.ls[n]=v.length>300?v.slice(0,300):v" +
        "}}}" +
        "catch(e6){o.lsErr=String(e6)}" +
        "try{o.cookie=String(document.cookie).slice(0,3000)}catch(e7){o.cookieErr=String(e7)}" +
        "try{for(var k in W){" +
        "try{" +
        "if(/chatgpt|oauth|access_token|session|account_id/i.test(k)){" +
        "var w=W[k];" +
        "o.win[k]=(typeof w==='string')?(w.length>300?w.slice(0,300):w):('['+typeof w+']')" +
        "}}catch(e8){}" +
        "}}catch(e9){o.winErr=String(e9)}" +
        "var res=[];" +
        "if(W.__CG_RES){for(var j=0;j<W.__CG_RES.length;j++){res.push(W.__CG_RES[j])}}" +
        "var sn='';" +
        "try{sn=JSON.stringify(o)}catch(e10){sn='{}'}" +
        "var out={u:String(location.href).slice(0,200),s:String(document.readyState),r:res,sn:sn};" +
        "var j0='';" +
        "try{j0=JSON.stringify(out)}catch(e11){j0='{}'}" +
        "if(!j0){j0='{}'}" +
        "return j0" +
        "}catch(e){" +
        "try{return JSON.stringify({u:String(location.href).slice(0,200),s:String(document.readyState),err:String(e)})}" +
        "catch(e12){return '{}'}" +
        "}})()"

    var onToken: ((CGToken) -> Void)?
    var onLive: ((String) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
        guard webView.url?.absoluteString.contains("chatgpt.com") == true else { return }
        warmup(webView, attempt: 1)
    }

    /// 页面落地后自动探测几轮：ChatGPT 是 SPA，didFinish 之后还会继续跳
    private func warmup(_ webView: WKWebView, attempt: Int) {
        webView.evaluateJavaScript(WKNavDelegate.probeJS) { [weak self] result, _ in
            guard let self = self else { return }
            guard let raw = result as? String, !raw.isEmpty else { return }
            let r = WKNavDelegate.parseProbe(raw)
            DispatchQueue.main.async {
                if !r.live.isEmpty { self.onLive?(r.live) }
                if let t = r.token { self.onToken?(t) }
            }
            if r.token == nil, attempt < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.warmup(webView, attempt: attempt + 1)
                }
            }
        }
    }

    /// 解析探测结果。诊断句一律用独立字面量拼接，不用字符串插值。
    static func parseProbe(_ raw: String) -> (token: CGToken?, src: String, msg: String, live: String) {
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, "", "探测返回不可解析", "未知")
        }
        if let err = root["err"] as? String {
            return (nil, "", "探测脚本执行出错：" + err, "异常")
        }
        if !(root["u"] is String) || !(root["s"] is String) {
            return (nil, "", "探测脚本没能正常返回 → 页面可能还没加载完，请再点一次", "异常")
        }
        let url = root["u"] as? String ?? ""
        let ready = root["s"] as? String ?? "?"

        var cands: [(String, String)] = []
        var eps: [(String, String)] = []
        if let arr = root["r"] as? [[String: Any]] {
            for x in arr {
                let u = x["u"] as? String ?? "?"
                let st = (x["s"] as? NSNumber)?.intValue ?? 0
                let body = x["b"] as? String ?? ""
                let er = x["e"] as? String ?? ""
                var name = u
                if u.hasSuffix("/api/auth/sessions") { name = "sessions" }
                else if u.hasSuffix("/api/auth/session") { name = "session" }
                if !er.isEmpty {
                    eps.append((name, er))
                } else if !body.isEmpty {
                    eps.append((name, "HTTP" + String(st)))
                    cands.append((name + " HTTP" + String(st), body))
                } else {
                    eps.append((name, "请求中"))
                }
            }
        }

        let snap: [String: Any]
        if let sraw = root["sn"] as? String,
           let sd = sraw.data(using: .utf8),
           let so = try? JSONSerialization.jsonObject(with: sd) as? [String: Any] {
            snap = so
        } else {
            snap = [:]
        }
        if let ls = snap["ls"] as? [String: Any] {
            for k in ls.keys.sorted() { cands.append(("localStorage[" + k + "]", ls[k] as? String ?? "")) }
        }
        if let ck = snap["cookie"] as? String { cands.append(("document.cookie", ck)) }
        if let w = snap["win"] as? [String: Any] {
            for k in w.keys.sorted() { cands.append(("window." + k, w[k] as? String ?? "")) }
        }

        // 1) 会话接口 JSON 里的 accessToken
        var tok = "", team = "", who = "", src = ""
        for c in cands {
            if !tok.isEmpty { break }
            guard let b = c.1.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: b) as? [String: Any] else { continue }
            if let v = o["accessToken"] as? String, !v.isEmpty {
                tok = v
                team = (o["teamAccount_id"] as? String) ?? ""
                who = (o["user"] as? String) ?? (o["username"] as? String) ?? (o["name"] as? String) ?? ""
                src = c.0
            }
        }

        // 2) obfuscated_oauth_token（cookie 串 / localStorage / sessionid 解一层）
        if tok.isEmpty {
            for c in cands {
                if let v = extract(c.1, key: "obfuscated_oauth_token"), !v.isEmpty {
                    tok = v
                    src = c.0
                    break
                }
            }
        }

        // 3) window.__chatgpt_session_token__
        if tok.isEmpty, let w = snap["win"] as? [String: Any],
           let v = w["__chatgpt_session_token__"] as? String, !v.isEmpty {
            tok = v
            team = (w["__chatgpt_account_id__"] as? String) ?? team
            src = "window.__chatgpt_session_token__"
        }

        // 4) localStorage / cookie 里的裸字符串 token（__chatgpt_session_token__ 等）
        if tok.isEmpty {
            for c in cands {
                if !tok.isEmpty { break }
                let key = c.0.lowercased()
                guard key.contains("session_token") || key.contains("oauth_token") else { continue }
                let v = c.1.trimmingCharacters(in: .whitespacesAndNewlines)
                guard v.count > 20, !v.hasPrefix("{"), !v.hasPrefix("["), !v.contains(";") else { continue }
                tok = v
                src = c.0
            }
        }

        // 会话接口状态（用于人话诊断）
        var sess = ""
        if let hit = eps.first(where: { $0.0 == "session" }) { sess = hit.1 }
        if sess.isEmpty, let hit = eps.first(where: { $0.0 == "sessions" }) { sess = hit.1 }
        // 有些部署返回 HTTP 200 + {"error":"Unauthorized"}，按未登录处理
        if let sbody = cands.first(where: { $0.0.hasPrefix("session") })?.1 {
            let low = sbody.lowercased()
            if low.contains("unauthorized") || low.contains("forbidden") { sess = "HTTP401" }
        }

        let tail = "页面 " + (url.isEmpty ? "未知" : url)
            + " ｜ ready=" + ready
            + " ｜ " + (eps.isEmpty ? "未发出请求" : eps.map { $0.0 + "→" + $0.1 }.joined(separator: " "))
            + " ｜ 候选 " + String(cands.count) + " 处"
        let msg = headMsg(sess: sess, epsEmpty: eps.isEmpty) + "\n" + tail

        guard !tok.isEmpty else {
            let lv: String
            if sess == "HTTP401" || sess == "HTTP403" { lv = "未登录" }
            else { lv = "未取到" }
            return (nil, "", msg, lv)
        }

        let t = CGToken()
        t.accessToken = tok
        t.teamAccountID = team
        t.label = who.isEmpty ? "web-user" : who
        t.note = "浏览器登录"
        t.status = "ok"
        let okMsg = "已获取凭证：" + t.label + "　来源 " + src + "\n" + tail
        return (t, src, okMsg, "已登录")
    }

    /// 诊断首句。字面量各自独立成常量，避免被 -O 常量池吞掉。
    private static func headMsg(sess: String, epsEmpty: Bool) -> String {
        if sess == "HTTP401" || sess == "HTTP403" {
            return "当前页面未登录 → 请在下方页面完成登录，再点一次「抓取 Token」"
        }
        if sess == "请求中" {
            return "会话接口还没返回 → 稍等再点一次「抓取 Token」"
        }
        if !sess.isEmpty && sess.hasPrefix("HTTP") {
            return "会话接口返回 " + sess + " 但没有 accessToken → 接口结构可能变了，请把下面这行原样发给我"
        }
        if !sess.isEmpty {
            return "请求会话接口失败：" + sess + " → 检查网络或 VPN"
        }
        if epsEmpty {
            return "还没发出会话请求 → 请把下面这行原样发给我"
        }
        return "没找到 accessToken → 请把下面这行原样发给我"
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
