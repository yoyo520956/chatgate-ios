import SwiftUI

// MARK: - 账号列表

struct TokensView: View {
    @EnvironmentObject var store: CGViewStore
    @State private var editing: CGToken? = nil
    @State private var showLogin = false
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: { showLogin = true }) {
                        Label("浏览器登录并自动抓取", systemImage: "safari")
                            .font(.system(size: CG.fBody, weight: .medium))
                            .foregroundStyle(CG.brand)
                    }
                    Button(action: { editing = CGToken() }) {
                        Label("手动粘贴 Token", systemImage: "square.and.pencil")
                            .font(.system(size: CG.fBody))
                            .foregroundStyle(CG.text1)
                    }
                }
                .listRowBackground(CG.surface)

                if store.tokens.isEmpty {
                    Section {
                        Text("还没有账号。网页版 access token 约 24 小时过期，建议用上面的按钮自动抓取。")
                            .font(.system(size: CG.fSmall))
                            .foregroundStyle(CG.text2)
                    }
                    .listRowBackground(CG.surface)
                } else {
                    Section("账号池（\(store.tokens.count)）") {
                        ForEach(store.tokens) { t in
                            TokenRowView(token: t,
                                         busy: store.busyTokenID == t.id,
                                         onEdit: { editing = t },
                                         onDelete: { store.removeToken(id: t.id) },
                                         onVerify: { verify(t) })
                        }
                    }
                    .listRowBackground(CG.surface)
                }

                Section {
                    HStack {
                        Label("使用说明", systemImage: "info.circle")
                        Text("多账号轮询，故障自动切换")
                    }
                    .font(.system(size: CG.fCaption))
                    .foregroundStyle(CG.text3)
                }
                .listRowBackground(CG.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CG.bg)
            .navigationTitle("账号")
            .sheet(isPresented: $showLogin) {
                TokenLoginView()
            }
            .sheet(item: $editing) { t in
                TokenEditView(token: t)
            }
            .sheet(isPresented: $showAdd) {
                TokenEditView(token: CGToken())
            }
        }
    }

    private func verify(_ t: CGToken) {
        guard !t.accessToken.isEmpty else { return }
        store.busyTokenID = t.id
        Task {
            let client = CGChatGPTClient()
            let body = client.buildChatGPTBody(CGChatRequest())
            do {
                let _ = try await client.prepare(token: t, body: body)
                var updated = t
                updated.status = "ok"
                updated.lastCheckedAt = Date()
                store.updateToken(updated)
            } catch {
                var updated = t
                updated.status = "invalid"
                updated.lastCheckedAt = Date()
                updated.note = "校验失败：\(error.localizedDescription)"
                store.updateToken(updated)
            }
            DispatchQueue.main.async { store.busyTokenID = nil }
        }
    }
}

// MARK: - 账号行

struct TokenRowView: View {
    let token: CGToken
    let busy: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onVerify: () -> Void

    private var statusColor: Color {
        if busy { return CG.accent }
        return token.status == "ok" ? CG.ok : (token.status == "invalid" ? CG.danger : CG.text2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CG.sp2) {
            HStack(spacing: CG.sp2) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(token.label.isEmpty ? token.masked : token.label)
                    .font(.system(size: CG.fBody, weight: .medium))
                    .foregroundStyle(CG.text1)
                    .lineLimit(1)
                Spacer()
                if let at = token.lastCheckedAt {
                    Text(at, style: .relative).font(.system(size: CG.fCaption))
                        .foregroundStyle(CG.text3)
                }
            }
            Text(token.masked).font(.system(size: CG.fCaption, design: .monospaced))
                .foregroundStyle(CG.text2).cgMono()
            HStack(spacing: CG.sp2) {
                Button(action: onVerify) {
                    Label(busy ? "校验中…" : "校验",
                          systemImage: busy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .font(.system(size: CG.fCaption))
                        .padding(.horizontal, CG.sp3).padding(.vertical, CG.sp1)
                        .background(CG.accent.opacity(0.16)).cornerRadius(CG.rS)
                        .foregroundStyle(CG.accent)
                }
                .disabled(busy)
                Button(action: onEdit) {
                    Label("编辑", systemImage: "pencil")
                        .font(.system(size: CG.fCaption))
                        .padding(.horizontal, CG.sp3).padding(.vertical, CG.sp1)
                        .background(CG.surface2).cornerRadius(CG.rS)
                        .foregroundStyle(CG.text1)
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: CG.fCaption))
                        .padding(CG.sp2)
                        .background(CG.danger.opacity(0.16)).cornerRadius(CG.rS)
                        .foregroundStyle(CG.danger)
                }
            }
            if !token.note.isEmpty {
                Text(token.note).font(.system(size: CG.fCaption))
                    .foregroundStyle(CG.text3).lineLimit(2)
            }
        }
        .padding(.top, CG.sp1)
    }
}
