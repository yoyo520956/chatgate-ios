import SwiftUI
import UIKit

// MARK: - 请求日志

struct LogsView: View {
    @EnvironmentObject var store: CGViewStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: CG.sp2) {
                if store.logs.isEmpty {
                    emptyState
                } else {
                    ForEach(store.logs) { LogRowView(entry: $0) }
                }
            }
            .padding(CG.sp4)
        }
        .background(CG.bg)
        .navigationTitle("请求日志")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) { store.clearLogs() } label: {
                        Label("清空日志", systemImage: "trash")
                    }
                    Button { store.resetStats() } label: {
                        Label("重置统计", systemImage: "arrow.counterclockwise")
                    }
                    Button { share() } label: {
                        Label("导出日志", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: CG.sp3) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(CG.text3)
            Text("还没有请求记录")
                .font(.system(size: CG.fBody))
                .foregroundStyle(CG.text2)
            Text("启动网关后，第三方软件发起的请求会实时记录在这里。")
                .font(.system(size: CG.fCaption))
                .foregroundStyle(CG.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(CG.sp8)
    }

    private func share() {
        let lines = store.logs.prefix(100).map { e in
            "[\(e.at)] \(e.method) \(e.path) \(e.status) \(e.ms)ms \(e.toolCallCount > 0 ? "tools=\(e.toolCallCount) " : "")\(e.error)"
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }
}

// MARK: - 日志行

struct LogRowView: View {
    let entry: CGRequestLog

    private var statusColor: Color {
        entry.status < 400 ? CG.ok : CG.danger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CG.sp1) {
            HStack(spacing: CG.sp2) {
                Text(entry.method)
                    .font(.system(size: CG.fCaption, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CG.accent)
                Text(entry.path)
                    .font(.system(size: CG.fCaption, design: .monospaced))
                    .foregroundStyle(CG.text1)
                    .lineLimit(1)
                Spacer()
                Text(String(entry.status))
                    .font(.system(size: CG.fCaption, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
            HStack(spacing: CG.sp2) {
                Text(entry.ms > 0 ? "\(entry.ms)ms" : "—")
                    .font(.system(size: CG.fCaption, design: .monospaced))
                    .foregroundStyle(CG.text2)
                if entry.stream {
                    chip("流式", CG.accent)
                }
                if entry.hasTools {
                    chip("tools=\(entry.toolCallCount)", CG.ok)
                }
                if !entry.model.isEmpty {
                    chip(entry.model.cgTrunc40, CG.text2)
                }
            }
            if !entry.error.isEmpty {
                Text(entry.error).font(.system(size: CG.fCaption))
                    .foregroundStyle(CG.danger).lineLimit(2)
            }
            Text(entry.at, style: .time)
                .font(.system(size: CG.fCaption, design: .monospaced))
                .foregroundStyle(CG.text3)
        }
        .padding(CG.sp3)
        .background(CG.surface)
        .cornerRadius(CG.rM)
        .overlay(RoundedRectangle(cornerRadius: CG.rM).stroke(CG.border, lineWidth: 0.5))
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: CG.fCaption, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, CG.sp2)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .cornerRadius(4)
    }
}
