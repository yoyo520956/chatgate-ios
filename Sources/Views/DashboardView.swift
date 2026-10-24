import SwiftUI
import UIKit

// MARK: - 仪表盘

struct DashboardView: View {
    @EnvironmentObject var store: CGViewStore
    @State private var copied = false
    @State private var showTokenHint = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CG.sp4) {
                    heroBanner
                    statusCard
                    endpointCard
                    hintCard
                    statsRow
                    quickLinks
                }
                .padding(CG.sp4)
            }
            .background(CG.bg)
            .navigationTitle("ChatGate")
            .toolbar {
                Button { showTokenHint = true } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
            .sheet(isPresented: $showTokenHint) {
                TokenLoginView().presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: 插画横幅
    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            Image("hero")
                .resizable()
                .scaledToFill()
                .frame(height: 168)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [CG.bg.opacity(0), CG.bg.opacity(0.55), CG.bg.opacity(0.92)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    LinearGradient(
                        colors: [CG.surface.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing)
                )
            VStack(alignment: .leading, spacing: CG.sp1) {
                Text("本机即网关").font(.system(size: CG.fTitle, weight: .bold))
                    .foregroundStyle(CG.text1)
                Text("ChatGPT 网页版 ⇄ OpenAI 兼容 API")
                    .font(.system(size: CG.fSmall))
                    .foregroundStyle(CG.text2)
            }
            .padding(CG.sp4)
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: CG.rL))
        .overlay(RoundedRectangle(cornerRadius: CG.rL).stroke(CG.border, lineWidth: 0.5))
    }

    // MARK: 状态卡
    private var statusCard: some View {
        VStack(spacing: CG.sp4) {
            HStack(spacing: CG.sp2) {
                Circle()
                    .fill(store.isRunning ? CG.ok : CG.danger)
                    .frame(width: 9, height: 9)
                Text(store.isRunning ? "网关运行中" : "网关已停止")
                    .font(.system(size: CG.fHead, weight: .semibold))
                    .foregroundStyle(CG.text1)
                Spacer()
                if store.tokens.isEmpty {
                    Label("无账号", systemImage: "exclamationmark.triangle")
                        .font(.system(size: CG.fCaption))
                        .foregroundStyle(CG.warn)
                        .padding(.horizontal, CG.sp2)
                        .padding(.vertical, CG.sp1)
                        .background(CG.warn.opacity(0.14))
                        .cornerRadius(CG.rS)
                }
            }
            Text(store.serverMessage)
                .font(.system(size: CG.fSmall))
                .foregroundStyle(CG.text2)
            Button(action: { store.toggle() }) {
                Label(store.isRunning ? "停止网关" : "启动网关",
                      systemImage: store.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: CG.fBody, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: CG.hitMin)
                    .background(store.isRunning ? CG.danger.opacity(0.18) : CG.brand)
                    .cornerRadius(CG.rM)
                    .foregroundStyle(store.isRunning ? CG.danger : .white)
            }
            if store.tokens.isEmpty {
                Button(action: { showTokenHint = true }) {
                    Text("先添加一个 ChatGPT 账号 Token →")
                        .font(.system(size: CG.fSmall, weight: .medium))
                        .foregroundStyle(CG.accent)
                }
            }
        }
        .cgCard()
    }

    // MARK: 端点卡
    private var endpointCard: some View {
        VStack(alignment: .leading, spacing: CG.sp3) {
            Text("接入端点").font(.system(size: CG.fSmall)).foregroundStyle(CG.text2)
            Text(store.endpointLine)
                .font(.system(size: CG.fSmall, design: .monospaced))
                .foregroundStyle(store.isRunning ? CG.ok : CG.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(CG.sp3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CG.bg.opacity(0.6))
                .cornerRadius(CG.rM)
                .overlay(RoundedRectangle(cornerRadius: CG.rM).stroke(CG.border, lineWidth: 0.5))
            if store.isRunning {
                HStack(spacing: CG.sp2) {
                    Button(action: copyEndpoint) {
                        Label(copied ? "已复制" : "复制本机端点",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: CG.fSmall, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(CG.brand)
                            .cornerRadius(CG.rS)
                            .foregroundStyle(.white)
                    }
                    Button(action: copyLan) {
                        Label(copied ? "已复制" : "复制局域网端点",
                              systemImage: copied ? "checkmark" : "wifi")
                            .font(.system(size: CG.fSmall, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(CG.surface2)
                            .cornerRadius(CG.rS)
                            .foregroundStyle(CG.text1)
                    }
                }
                Text("局域网：\(store.lanURL)")
                    .font(.system(size: CG.fCaption, design: .monospaced))
                    .foregroundStyle(CG.text2)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("局域网内的电脑/手机可用该地址接入；仅限同一 WiFi。")
                    .font(.system(size: CG.fCaption))
                    .foregroundStyle(CG.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cgCard()
    }

    // MARK: 提示卡
    private var hintCard: some View {
        VStack(alignment: .leading, spacing: CG.sp2) {
            Text("接入步骤").font(.system(size: CG.fSmall)).foregroundStyle(CG.text2)
            Text("1. 在「账号」页添加 ChatGPT access token\n2. 点「启动网关」\n3. 把端点填进第三方软件（详见「接入」页）")
                .font(.system(size: CG.fSmall))
                .foregroundStyle(CG.text1)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cgCard()
    }

    // MARK: 统计
    private var statsRow: some View {
        HStack(spacing: CG.sp3) {
            statItem(store.stats.totalRequests, "请求")
            statItem(store.stats.totalToolCalls, "工具调用")
            statItem(store.stats.totalErrors, "失败")
        }
        .cgCard()
    }

    private func statItem(_ value: Int, _ title: String) -> some View {
        VStack(spacing: CG.sp1) {
            Text("\(value)").font(.system(size: CG.fTitle, weight: .bold)).foregroundStyle(CG.text1)
            Text(title).font(.system(size: CG.fCaption)).foregroundStyle(CG.text2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 快捷入口
    private var quickLinks: some View {
        NavigationLink { LogsView() } label: {
            HStack {
                Label("请求日志", systemImage: "list.bullet.rectangle")
                    .font(.system(size: CG.fBody, weight: .medium))
                    .foregroundStyle(CG.text1)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(CG.text3)
            }
            .cgCard()
        }
        .buttonStyle(.plain)
    }

    private func copyEndpoint() {
        UIPasteboard.general.string = store.endpointLine
        copied = true
        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); copied = false }
    }
    private func copyLan() {
        UIPasteboard.general.string = store.lanURL
        copied = true
        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); copied = false }
    }
}
