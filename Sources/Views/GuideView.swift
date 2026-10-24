import SwiftUI
import UIKit

// MARK: - 接入指南

struct GuideView: View {
    @EnvironmentObject var store: CGViewStore
    @State private var copiedIdx = -1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CG.sp4) {
                    endpointBanner
                    authNote
                    stepSection
                    ForEach(Array(configs.enumerated()), id: \.offset) { i, c in
                        ConfigCard(item: c, copied: copiedIdx == i, onCopy: { copy(c.body, i) })
                    }
                    curlCard
                    disclaimer
                }
                .padding(CG.sp4)
            }
            .background(CG.bg)
            .navigationTitle("接入第三方软件")
        }
    }

    private var endpoint: String {
        store.isRunning ? store.localURL : "http://127.0.0.1:\(store.settings.port)"
    }

    private var endpointBanner: some View {
        VStack(alignment: .leading, spacing: CG.sp2) {
            Text("端点地址（Base URL）").font(.system(size: CG.fSmall)).foregroundStyle(CG.text2)
            Text(endpoint)
                .font(.system(size: CG.fBody, design: .monospaced))
                .foregroundStyle(store.isRunning ? CG.ok : CG.warn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cgCard()
    }

    private var authNote: some View {
        HStack(spacing: CG.sp2) {
            Image(systemName: "lock.shield")
                .foregroundStyle(!store.settings.authEnabled || store.settings.authKey.isEmpty ? CG.text2 : CG.warn)
            Text(!store.settings.authEnabled || store.settings.authKey.isEmpty
                 ? "当前未开启鉴权，API Key 可填任意值（如 sk-x）"
                 : "已开启鉴权，API Key 必须填：\(store.settings.authKey)")
                .font(.system(size: CG.fCaption))
                .foregroundStyle(!store.settings.authEnabled || store.settings.authKey.isEmpty ? CG.text2 : CG.warn)
                .cgMono()
        }
        .cgCard()
    }

    private var stepSection: some View {
        VStack(alignment: .leading, spacing: CG.sp2) {
            Text("三步接入").font(.system(size: CG.fSmall)).foregroundStyle(CG.text2)
            Text("① 本机启动网关\n② 按下方任一软件填写 Base URL 与 API Key\n③ 模型名填 gpt-4o 即可")
                .font(.system(size: CG.fSmall))
                .foregroundStyle(CG.text1)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cgCard()
    }

    private var configs: [ConfigItem] {
        [
            ConfigItem(
                name: "Cherry Studio",
                icon: "sparkles",
                note: "设置 → 模型服务 → 自定义 OpenAI 接口",
                body: """
Base URL: \(endpoint)/v1
API Key:  sk-x（未鉴权时任意）
模型: gpt-4o
"""),
            ConfigItem(
                name: "LobeChat",
                icon: "message",
                note: "设置 → 模型提供方 → OpenAI → 自定义 API 路由",
                body: """
Base URL: \(endpoint)/v1
API Key:  sk-x
模型: gpt-4o
"""),
            ConfigItem(
                name: "Cline / Roo Code",
                icon: "terminal",
                note: "设置 → OpenAI Compatible API",
                body: """
Base URL: \(endpoint)
API Key:  sk-x
Model ID: gpt-4o
"""),
            ConfigItem(
                name: "Open WebUI",
                icon: "play.rectangle",
                note: "管理 → Connections → OpenAI API",
                body: """
Base URL: \(endpoint)/v1
API Key:  sk-x
Model: gpt-4o
"""),
        ]
    }

    private var curlCard: some View {
        VStack(alignment: .leading, spacing: CG.sp3) {
            Text("命令行验证").font(.system(size: CG.fSmall)).foregroundStyle(CG.text2)
            Text("curl \(endpoint)/v1/chat/completions -H \"Content-Type: application/json\" -d '{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'")
                .font(.system(size: CG.fCaption, design: .monospaced))
                .foregroundStyle(CG.text1)
                .lineSpacing(4)
                .padding(CG.sp3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CG.bg.opacity(0.6))
                .cornerRadius(CG.rS)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cgCard()
    }

    private var disclaimer: some View {
        Text("注意：仅限同一设备（本机 127.0.0.1）或同一 WiFi（局域网地址）。请勿在公网暴露本服务。")
            .font(.system(size: CG.fCaption))
            .foregroundStyle(CG.text3)
            .lineSpacing(4)
    }

    private func copy(_ text: String, _ idx: Int) {
        UIPasteboard.general.string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        copiedIdx = idx
        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); copiedIdx = -1 }
    }
}

// MARK: - 配置项

struct ConfigItem {
    var name: String
    var icon: String
    var note: String
    var body: String
}

// MARK: - 配置卡

struct ConfigCard: View {
    let item: ConfigItem
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CG.sp3) {
            HStack(spacing: CG.sp2) {
                Image(systemName: item.icon)
                    .font(.system(size: CG.fBody))
                    .foregroundStyle(CG.brand)
                Text(item.name)
                    .font(.system(size: CG.fHead, weight: .semibold))
                    .foregroundStyle(CG.text1)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: CG.fSmall))
                        .foregroundStyle(copied ? CG.ok : CG.text2)
                        .frame(width: CG.hitMin, height: CG.hitMin)
                }
            }
            Text(item.note)
                .font(.system(size: CG.fCaption))
                .foregroundStyle(CG.text2)
            Text(item.body)
                .font(.system(size: CG.fSmall, design: .monospaced))
                .foregroundStyle(CG.text1)
                .lineSpacing(5)
                .padding(CG.sp3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CG.bg.opacity(0.6))
                .cornerRadius(CG.rS)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cgCard()
    }
}
