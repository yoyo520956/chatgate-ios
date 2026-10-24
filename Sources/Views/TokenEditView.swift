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
        webView.evaluateJavaScript(WKNavDelegate.sessionJS) { [self] result, error in
            if let raw = result as? String, !raw.isEmpty, let data = raw.data(using: .utf8),
               let t = WKNavDelegate.parseToken(data) {
                self.found = t
                self.note = "已获取凭证：\(t.label)"
            } else {
                self.note = error == nil
                    ? "未取到凭证，请先点「打开登录页」完成登录"
                    : "读取失败：\(error?.localizedDescription ?? "未知错误")"
            }
            self.busy = false
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

    static let sessionJS =
        "fetch('/api/auth/session',{credentials:'include'})" +
        ".then(function(r){return r.text()})" +
        ".catch(function(e){return ''})"

    var onToken: ((CGToken) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
        guard webView.url?.absoluteString.contains("chatgpt.com") == true else { return }
        let js = WKNavDelegate.sessionJS
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let raw = result as? String, !raw.isEmpty,
                  let data = raw.data(using: .utf8) else { return }
            if let t = WKNavDelegate.parseToken(data) {
                self?.onToken?(t)
            }
        }
    }

    static func parseToken(_ data: Data) -> CGToken? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let token = (obj["accessToken"] as? String) ?? ""
        guard !token.isEmpty else { return nil }
        var t = CGToken()
        t.label = (obj["user"] as? String)
            ?? (obj["username"] as? String)
            ?? (obj["name"] as? String)
            ?? "web-user"
        t.accessToken = token
        t.teamAccountID = (obj["teamAccount_id"] as? String) ?? ""
        t.note = "浏览器登录"
        t.status = "ok"
        return t
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
