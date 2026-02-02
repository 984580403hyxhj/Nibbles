import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 🎨 Premium Theme System
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum Theme {
    
    // MARK: - Color Palette
    enum Colors {
        // Text
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.7)
        static let textTertiary = Color.white.opacity(0.5)
        
        // Accents
        static let accent = Color(hex: "00D4AA")        // Mint green
        static let accentSecondary = Color(hex: "6C5CE7") // Purple
        static let accentWarm = Color(hex: "FDCB6E")    // Gold
        
        // Backgrounds
        static let bgDeep = Color(hex: "0A0A0F")
        static let bgCard = Color(hex: "14141F")
        static let bgElevated = Color(hex: "1E1E2D")
        static let bgOverlay = Color.black.opacity(0.85)
        
        // Level Colors
        static let level1 = Color(hex: "FF6B6B")  // Coral
        static let level2 = Color(hex: "FDCB6E")  // Gold
        static let level3 = Color(hex: "00D4AA")  // Mint
        
        static func forLevel(_ level: Int) -> Color {
            switch level {
            case 1: return level1
            case 2: return level2
            case 3: return level3
            default: return accent
            }
        }
    }
    
    // MARK: - Typography
    enum Font {
        static let largeTitle = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded)
        static let title = SwiftUI.Font.system(size: 22, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 16, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 13, weight: .medium)
        static let micro = SwiftUI.Font.system(size: 11, weight: .semibold)
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
    
    // MARK: - Radius
    enum Radius {
        static let card: CGFloat = 24
        static let button: CGFloat = 12
        static let badge: CGFloat = 8
    }
    
    // MARK: - Tag Icons
    static let tagIcons: [String: String] = [
        "人性的高光": "✨", "趣味事实": "🎯", "审美指纹": "🎨",
        "见闻发散": "🌍", "现地现物": "⚡", "技术奇点": "🚀",
        "安全哲学": "🛡", "物理底层": "⚛️", "中国计算": "🇨🇳",
        "格局重塑": "📈", "文明进阶": "🌟", "太空算力": "🛰",
        "原子革命": "🔬", "机器人学": "🤖", "教育重构": "📚",
        "人类终局": "🌌", "星际演化": "🪐", "生物限制": "🧬",
        "脑机进化": "🧠", "太空工业": "🏭", "思维主权": "💭",
        "底层逻辑": "🧩", "商业演化": "💎", "生命哲学": "☯️",
        "风险逻辑": "🎲", "第一性原理": "📐"
    ]
    
    static func icon(for tag: String) -> String {
        tagIcons[tag] ?? "💡"
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 🎴 Premium Card Components
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PremiumCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.Colors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.white.opacity(0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
    }
}

extension View {
    func premiumCard() -> some View {
        modifier(PremiumCard())
    }
}

struct LevelIndicator: View {
    let level: Int
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= level ? Theme.Colors.forLevel(level) : Color.white.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

struct TagLabel: View {
    let tag: String
    
    var body: some View {
        HStack(spacing: 6) {
            Text(Theme.icon(for: tag))
                .font(.system(size: 14))
            Text(tag)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }
}
