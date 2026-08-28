import SwiftUI
import UIKit

/// 全局主题：主色 + 课程卡片配色，全部支持深浅色模式
enum Theme {
    /// 主色（深色模式下提亮，避免看不清）
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.72, blue: 1.0, alpha: 1)
            : UIColor(red: 0.02, green: 0.47, blue: 0.96, alpha: 1)
    })

    /// 压在 accent 上的文字色（浅色=白，深色=深蓝）
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.15, blue: 0.30, alpha: 1)
            : UIColor.white
    })

    /// 登录页顶部渐变起点（浅色=淡蓝，深色=深蓝黑）
    static let gradientTop = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.11, blue: 0.20, alpha: 1)
            : UIColor(red: 0.91, green: 0.96, blue: 1.0, alpha: 1)
    })

    /// 卡片底色（浅色=白，深色=深灰）
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
            : UIColor.white
    })

    /// “今天”列的高亮底色
    static let todayTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 0.45)
            : UIColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 0.14)
    })

    /// “现在”这一节所在行的底色
    static let nowTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.72, blue: 1.0, alpha: 0.16)
            : UIColor(red: 0.02, green: 0.47, blue: 0.96, alpha: 0.07)
    })

    // MARK: - 课程卡片配色（10 组，每组含浅色/深色两套底色与文字色）

    private struct PaletteEntry {
        let lightBG: (CGFloat, CGFloat, CGFloat)
        let darkBG: (CGFloat, CGFloat, CGFloat)
        let lightFG: (CGFloat, CGFloat, CGFloat)
        let darkFG: (CGFloat, CGFloat, CGFloat)
    }

    private static let palette: [PaletteEntry] = [
        // 蓝 / 绿 / 橙 / 粉 / 紫 / 靛 / 青 / 黄 / 薄荷 / 珊瑚
        PaletteEntry(lightBG: (0.85, 0.92, 1.00), darkBG: (0.13, 0.22, 0.38),
                     lightFG: (0.12, 0.32, 0.60), darkFG: (0.78, 0.87, 1.00)),
        PaletteEntry(lightBG: (0.87, 0.96, 0.87), darkBG: (0.12, 0.28, 0.16),
                     lightFG: (0.16, 0.45, 0.20), darkFG: (0.75, 0.92, 0.80)),
        PaletteEntry(lightBG: (1.00, 0.93, 0.83), darkBG: (0.38, 0.25, 0.10),
                     lightFG: (0.55, 0.30, 0.05), darkFG: (1.00, 0.88, 0.70)),
        PaletteEntry(lightBG: (1.00, 0.89, 0.93), darkBG: (0.38, 0.16, 0.22),
                     lightFG: (0.55, 0.15, 0.30), darkFG: (1.00, 0.80, 0.88)),
        PaletteEntry(lightBG: (0.93, 0.88, 1.00), darkBG: (0.28, 0.20, 0.40),
                     lightFG: (0.35, 0.20, 0.55), darkFG: (0.88, 0.80, 1.00)),
        PaletteEntry(lightBG: (0.88, 0.90, 1.00), darkBG: (0.20, 0.22, 0.40),
                     lightFG: (0.20, 0.25, 0.50), darkFG: (0.82, 0.85, 1.00)),
        PaletteEntry(lightBG: (0.85, 0.95, 1.00), darkBG: (0.10, 0.27, 0.32),
                     lightFG: (0.05, 0.35, 0.45), darkFG: (0.75, 0.93, 1.00)),
        PaletteEntry(lightBG: (1.00, 0.96, 0.85), darkBG: (0.40, 0.30, 0.10),
                     lightFG: (0.50, 0.35, 0.05), darkFG: (1.00, 0.92, 0.70)),
        PaletteEntry(lightBG: (0.86, 0.98, 0.93), darkBG: (0.10, 0.28, 0.20),
                     lightFG: (0.05, 0.40, 0.30), darkFG: (0.75, 0.95, 0.85)),
        PaletteEntry(lightBG: (1.00, 0.91, 0.88), darkBG: (0.40, 0.18, 0.14),
                     lightFG: (0.55, 0.20, 0.15), darkFG: (1.00, 0.85, 0.78)),
    ]

    /// 根据课程序号稳定取一组配色（同一门课永远同色，深浅色模式各有一套）
    static func courseColors(for key: String) -> (background: Color, foreground: Color) {
        var h: UInt64 = 5381
        for b in key.unicodeScalars { h = h &* 33 &+ UInt64(b.value) }
        let p = palette[Int(h % UInt64(palette.count))]
        let bg = Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? p.darkBG : p.lightBG
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        let fg = Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? p.darkFG : p.lightFG
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        return (bg, fg)
    }
}
