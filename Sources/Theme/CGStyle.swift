import SwiftUI

/// ChatGate 设计 tokens（单一来源，全局引用常量，禁裸值）
enum CG {
    // MARK: 色
    static let bg = Color(red: 0.06, green: 0.07, blue: 0.09)            // 页面底
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.15)       // 卡片
    static let surface2 = Color(red: 0.15, green: 0.16, blue: 0.20)      // 卡片高亮
    static let border = Color.white.opacity(0.10)                        // 发丝线
    static let text1 = Color.white.opacity(0.92)                         // 主文字
    static let text2 = Color.white.opacity(0.55)                         // 次文字
    static let text3 = Color.white.opacity(0.32)                         // 弱文字
    static let brand = Color(red: 0.06, green: 0.64, blue: 0.50)         // OpenAI 绿 #10A37F
    static let brandSoft = Color(red: 0.06, green: 0.64, blue: 0.50).opacity(0.16)
    static let accent = Color(red: 0.35, green: 0.55, blue: 1.0)         // 蓝（信息）
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.25)           // 橙
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)         // 红
    static let ok = Color(red: 0.30, green: 0.85, blue: 0.55)            // 绿灯

    // MARK: 圆角阶梯
    static let rS: CGFloat = 8
    static let rM: CGFloat = 12
    static let rL: CGFloat = 16
    static let rXL: CGFloat = 20

    // MARK: 间距（4pt 网格）
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 20
    static let sp6: CGFloat = 24
    static let sp8: CGFloat = 32

    // MARK: 字号
    static let fCaption: CGFloat = 11
    static let fSmall: CGFloat = 13
    static let fBody: CGFloat = 15
    static let fHead: CGFloat = 17
    static let fTitle: CGFloat = 22
    static let fHero: CGFloat = 28

    // MARK: 组件
    static let hitMin: CGFloat = 44
}

extension View {
    func cgCard() -> some View {
        self.padding(CG.sp4)
            .background(CG.surface)
            .cornerRadius(CG.rL)
            .overlay(RoundedRectangle(cornerRadius: CG.rL).stroke(CG.border, lineWidth: 0.5))
    }
    func cgMono() -> some View {
        font(.system(size: CG.fSmall, design: .monospaced))
    }
}

extension String {
    var cgTrunc40: String { count > 40 ? prefix(37) + "..." : self }
}
