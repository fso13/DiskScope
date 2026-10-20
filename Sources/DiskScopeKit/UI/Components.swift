import AppKit
import SwiftUI

// MARK: - Building blocks

/// The app mark: a gradient squircle with a small treemap, matching the icon.
struct AppMark: View {
    var size: CGFloat = 30

    var body: some View {
        let corner = size * 0.29
        let inset = size * 0.22
        let gap = max(1.4, size * 0.035)
        let inner = size - inset * 2
        let leftWidth = (inner - gap) * 0.52
        let rightWidth = inner - gap - leftWidth

        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.accent, Theme.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                HStack(spacing: gap) {
                    RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                        .fill(Color.white.opacity(0.94))
                        .frame(width: leftWidth)
                    VStack(spacing: gap) {
                        RoundedRectangle(cornerRadius: size * 0.045, style: .continuous)
                            .fill(Color.white.opacity(0.74))
                        RoundedRectangle(cornerRadius: size * 0.045, style: .continuous)
                            .fill(Color.white.opacity(0.48))
                    }
                    .frame(width: rightWidth)
                }
                .frame(width: inner, height: inner)
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .frame(width: size, height: size)
    }
}

struct NodeIcon: View {
    let category: FileCategory
    let isContainer: Bool
    var size: CGFloat = 24

    var body: some View {
        let color = isContainer ? Theme.folderColor(category) : Theme.categoryColor(category)
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(color.opacity(0.15))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundStyle(color)
            )
            .frame(width: size, height: size)
    }

    private var symbol: String {
        if isContainer {
            return category == .app ? "app.fill" : "folder.fill"
        }
        return category.symbolName
    }
}

struct CategoryDot: View {
    let category: FileCategory
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(Theme.categoryColor(category))
            .frame(width: size, height: size)
    }
}

struct StatPill: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.subtleFill, in: Capsule())
    }
}

struct ProgressBar: View {
    let fraction: Double
    var tint: AnyShapeStyle = AnyShapeStyle(
        LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .leading, endPoint: .trailing)
    )
    var track: Color = Color.primary.opacity(0.07)
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(fraction <= 0 ? 0 : 4, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

struct SegmentedTabs: View {
    @Binding var selection: AppModel.Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppModel.Tab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.card)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(hint(for: tab))
            }
        }
        .padding(2)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func hint(for tab: AppModel.Tab) -> String {
        switch tab {
        case .map: return "Карта папки (⌘1)"
        case .largest: return "Самые крупные объекты (⌘2)"
        case .types: return "Распределение по типам (⌘3)"
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Фильтр по имени"
    var width: CGFloat = 190

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: width)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

struct IconActionButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = .primary
    var disabled = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 28)
                .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : tint)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering && !disabled ? Theme.subtleFill : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct AccentButton: View {
    let title: String
    let symbol: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accentDeep],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Theme.accent.opacity(hovering ? 0.45 : 0.28), radius: hovering ? 10 : 7, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct GhostButton: View {
    let title: String
    var symbol: String?
    var tint: Color = .primary
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Theme.subtleFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(hovering ? Theme.border : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct EmptyFolderView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

struct PermissionBanner: View {
    let count: Int
    let onDetails: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Нет доступа к \(Plural.items(count))")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Включите «Полный доступ к диску», чтобы увидеть служебные папки и точную картину.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GhostButton(title: "Подробнее", symbol: "info.circle", action: onDetails)
            GhostButton(title: "Настройки", symbol: "gearshape", tint: Theme.accent, action: onSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.warning.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.25), lineWidth: 1)
        )
    }
}

struct CategoryFilterChip: View {
    let category: FileCategory
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            CategoryDot(category: category)
            Text(category.title)
                .font(.system(size: 11, weight: .semibold))
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.subtleFill, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct ToastView: View {
    let toast: AppModel.Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: toast.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.success)
            Text(toast.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

// MARK: - Window configuration

/// Makes the chromeless window movable by dragging any empty area,
/// which is what people expect from a hidden-titlebar app.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.085, alpha: 1)
    }
}
