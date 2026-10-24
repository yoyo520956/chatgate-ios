import SwiftUI

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: CGViewStore

    var body: some View {
        Form {
            Section("网关") {
                Stepper("监听端口：\(store.settings.port)",
                        value: $store.settings.port, in: 1024...65535, step: 1)
                Toggle("开启访问鉴权", isOn: $store.settings.authEnabled)
                if store.settings.authEnabled {
                    SecureField("鉴权密钥（第三方软件填这个）", text: $store.settings.authKey)
                        .font(.system(size: CG.fSmall, design: .monospaced))
                }
                Button("随机生成密钥") { store.settings.authKey = CGSettings.randomKey() }
                    .font(.system(size: CG.fBody))
                    .foregroundStyle(CG.brand)
                    .disabled(!store.settings.authEnabled)
            }
            .listRowBackground(CG.surface)

            Section("上游") {
                TextField("代理地址（留空直连）", text: $store.settings.proxyURL)
                    .font(.system(size: CG.fSmall, design: .monospaced))
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                Picker("模型", selection: $store.settings.modelSlug) {
                    Text("auto（网页默认）").tag("auto")
                    Text("gpt-4o").tag("gpt-4o")
                    Text("gpt-4.1").tag("gpt-4.1")
                    Text("gpt-5").tag("gpt-5")
                }
                Picker("思考强度", selection: $store.settings.thinkingEffort) {
                    Text("standard").tag("standard")
                    Text("extended").tag("extended")
                    Text("max").tag("max")
                }
                Toggle("关闭历史记录", isOn: $store.settings.historyDisabled)
            }
            .listRowBackground(CG.surface)

            Section("运行") {
                Toggle("后台保活（静音音频，App 切后台仍服务）", isOn: $store.settings.keepAwake)
                Text("开启后 App 切到后台不会立刻被系统挂起，方便第三方软件持续调用。会略微增加耗电。")
                    .font(.system(size: CG.fCaption))
                    .foregroundStyle(CG.text3)
            }
            .listRowBackground(CG.surface)

            Section("数据") {
                Button(role: .destructive) { store.clearLogs() } label: {
                    Label("清空请求日志", systemImage: "trash")
                }
                Button { store.resetStats() } label: {
                    Label("重置统计", systemImage: "arrow.counterclockwise")
                }
            }
            .listRowBackground(CG.surface)

            Section("版本") {
                HStack {
                    Text("版本号").foregroundStyle(CG.text2)
                    Spacer()
                    Text("v\(CGVersion.bundleShort)").foregroundStyle(CG.text1).cgMono()
                }
                HStack {
                    Text("构建号").foregroundStyle(CG.text2)
                    Spacer()
                    Text(CGVersion.bundleBuild).foregroundStyle(CG.text1).cgMono()
                }
            }
            .listRowBackground(CG.surface)
        }
        .onChange(of: store.settings) { _ in store.save() }
        .scrollContentBackground(Visibility.hidden)
        .background(CG.bg)
        .navigationTitle("设置")
    }
}
