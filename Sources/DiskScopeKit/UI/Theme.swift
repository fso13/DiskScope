import AppKit
import SwiftUI

enum Theme {
    static let sidebarWidth: CGFloat = 238

    static let accent = Color(red: 0.34, green: 0.53, blue: 1.0)
    static let accentDeep = Color(red: 0.58, green: 0.36, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.38)
    static let warning = Color(red: 1.0, green: 0.66, blue: 0.22)
    static let success = Color(red: 0.27, green: 0.82, blue: 0.55)

    static let background = dynamic(
        light: NSColor(calibratedRed: 0.955, green: 0.965, blue: 0.98, alpha: 1),
        dark: NSColor(calibratedRed: 0.050, green: 0.060, blue: 0.078, alpha: 1)
    )
    static let card = dynamic(
        light: .white,
        dark: NSColor(calibratedRed: 0.086, green: 0.102, blue: 0.125, alpha: 1)
    )
    static let cardAlt = dynamic(
        light: NSColor(calibratedRed: 0.973, green: 0.978, blue: 0.988, alpha: 1),
        dark: NSColor(calibratedRed: 0.106, green: 0.122, blue: 0.148, alpha: 1)
    )
    static let border = dynamic(
        light: NSColor(calibratedWhite: 0, alpha: 0.075),
        dark: NSColor(calibratedWhite: 1, alpha: 0.09)
    )
    static let subtleFill = dynamic(
        light: NSColor(calibratedWhite: 0, alpha: 0.045),
        dark: NSColor(calibratedWhite: 1, alpha: 0.065)
    )
    static let sidebarTop = Color(red: 0.086, green: 0.102, blue: 0.145)
    static let sidebarBottom = Color(red: 0.051, green: 0.062, blue: 0.09)

    static func categoryColor(_ category: FileCategory) -> Color {
        switch category {
        case .video: return Color(red: 0.55, green: 0.49, blue: 1.0)
        case .image: return Color(red: 0.18, green: 0.80, blue: 0.61)
        case .audio: return Color(red: 0.94, green: 0.42, blue: 0.66)
        case .archive: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .document: return Color(red: 0.30, green: 0.55, blue: 1.0)
        case .app: return Color(red: 0.44, green: 0.52, blue: 1.0)
        case .code: return Color(red: 0.27, green: 0.79, blue: 0.48)
        case .other: return Color(red: 0.57, green: 0.62, blue: 0.70)
        }
    }

    static func folderColor(_ category: FileCategory) -> Color {
        category == .other ? Color(red: 0.42, green: 0.58, blue: 1.0) : categoryColor(category)
    }

    private static let containerPalette: [Color] = [
        Color(red: 0.29, green: 0.42, blue: 1.00),
        Color(red: 0.48, green: 0.30, blue: 1.00),
        Color(red: 0.24, green: 0.51, blue: 1.00),
        Color(red: 0.12, green: 0.62, blue: 0.78),
        Color(red: 0.36, green: 0.44, blue: 1.00),
        Color(red: 0.54, green: 0.30, blue: 0.88),
    ]

    /// Containers without a meaningful dominant file type get a rotating cool
    /// palette so a map full of .app bundles still reads as a map.
    static func treemapColor(category: FileCategory, seed: Int, isContainer: Bool) -> Color {
        if isContainer, category == .other || category == .app {
            let index = abs(seed &* 31 &+ 7) % containerPalette.count
            return containerPalette[index]
        }
        return categoryColor(category)
    }

    /// Dark text on light cells (images, archives, audio, code) keeps labels readable.
    static func treemapUsesDarkText(category: FileCategory, isContainer: Bool) -> Bool {
        switch category {
        case .image, .archive, .audio, .code: return true
        default: return false
        }
    }

    static func treemapTextColor(category: FileCategory, isContainer: Bool) -> Color {
        treemapUsesDarkText(category: category, isContainer: isContainer)
            ? Color.black.opacity(0.74)
            : Color.white.opacity(0.97)
    }

    static func treemapSecondaryTextColor(category: FileCategory, isContainer: Bool) -> Color {
        treemapUsesDarkText(category: category, isContainer: isContainer)
            ? Color.black.opacity(0.48)
            : Color.white.opacity(0.74)
    }

    static func gradient(for category: FileCategory) -> LinearGradient {
        let base = categoryColor(category)
        return LinearGradient(
            colors: [base.opacity(0.98), base.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        })
    }
}

enum AppFont {
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static let caption = Font.system(size: 11, weight: .medium)
    static let tiny = Font.system(size: 10, weight: .medium)
}

extension View {
    func cardSurface(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 5)
    }

    func innerSurface(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.subtleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}
