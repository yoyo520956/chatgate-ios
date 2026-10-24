import SwiftUI

@main
struct ChatGateApp: App {
    @StateObject private var store = CGViewStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(CG.brand)
                .environmentObject(store)
                .task { store.start() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: CGViewStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("网关", systemImage: "square.stack.3d.up.right") }
            TokensView()
                .tabItem { Label("账号", systemImage: "person.crop.circle") }
            PlaygroundView()
                .tabItem { Label("实测", systemImage: "play.circle") }
            GuideView()
                .tabItem { Label("接入", systemImage: "link") }
            MoreView()
                .tabItem { Label("更多", systemImage: "ellipsis") }
        }
    }
}

// MARK: - 更多：日志 + 设置 二级导航

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { LogsView() } label: {
                    Label("请求日志", systemImage: "list.bullet.rectangle")
                }
                NavigationLink { SettingsView() } label: {
                    Label("设置", systemImage: "gearshape")
                }
                NavigationLink { AboutView() } label: {
                    Label("关于 ChatGate", systemImage: "info.circle")
                }
            }
            .background(CG.bg)
            .navigationTitle("更多")
        }
    }
}

// MARK: - 关于页

struct AboutView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CG.sp5) {
                Image("AppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .cornerRadius(CG.rL)
                VStack(alignment: .leading, spacing: CG.sp2) {
                    Text("ChatGate").font(.system(size: CG.fTitle, weight: .bold))
                    Text("v\(CGVersion.bundleShort) · build \(CGVersion.bundleBuild)")
                        .font(.system(size: CG.fSmall)).foregroundStyle(CG.text2).cgMono()
                }
                Text("把 ChatGPT 网页版变成 OpenAI 兼容 API 网关。内嵌 tool calling 协议，可接入 Cherry Studio、LobeChat、Cline 等第三方软件。")
                    .font(.system(size: CG.fBody))
                    .foregroundStyle(CG.text1)
                    .lineSpacing(5)
                Divider().overlay(CG.border)
                Text("免责声明：本工具仅供个人学习研究。请勿商用、勿过度调用、勿转售，因使用本工具产生的一切后果由使用者自行承担。")
                    .font(.system(size: CG.fCaption))
                    .foregroundStyle(CG.text3)
                    .lineSpacing(3)
                Spacer()
            }
            .padding(CG.sp6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CG.bg)
            .navigationTitle("关于")
        }
    }
}
