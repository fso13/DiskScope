import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    volumeCard
                    quickAccess
                }
                .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
    }

    private var sidebarBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.sidebarTop, Theme.sidebarBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.14), Color.clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }

    private var volumeCard: some View {
        Button {
            if let volume = model.internalVolume {
                model.scanVolume(volume)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(model.internalVolume?.name ?? "Macintosh HD")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let volume = model.internalVolume {
                        Text(ByteFormat.percent(volume.usedBytes, of: volume.totalBytes))
                            .font(AppFont.number(13))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                if let volume = model.internalVolume {
                    ProgressBar(
                        fraction: volume.usedFraction,
                        tint: AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.white.opacity(0.95), Color.white.opacity(0.55)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        ),
                        track: Color.white.opacity(0.16),
                        height: 5
                    )

                    if model.isScanning {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                            Text(model.progress.map { "Сканируем · \(ByteFormat.string($0.bytes))" } ?? "Сканируем…")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text("Свободно \(ByteFormat.string(volume.freeBytes))")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer(minLength: 0)
                            Text("из \(ByteFormat.string(volume.totalBytes))")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                    }
                } else {
                    Text("Нет доступных томов")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.20, green: 0.29, blue: 0.55),
                                    Color(red: 0.32, green: 0.22, blue: 0.58),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 84, height: 84)
                        .blur(radius: 20)
                        .offset(x: 64, y: -26)
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help("Сканировать \(model.internalVolume?.name ?? "диск")")
    }

    private var quickAccess: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("БЫСТРЫЙ ДОСТУП")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.leading, 9)
                .padding(.bottom, 2)

            ForEach(locations) { location in
                SidebarRow(
                    location: location,
                    isActive: model.tab != .media && model.phase == .ready && model.tree?.rootPath == location.path,
                    isScanning: model.isScanning && model.progress?.currentPath.hasPrefix(location.path) == true
                ) {
                    model.scan(path: location.path)
                }
            }

            SidebarRow(
                location: SidebarLocation(
                    title: "Выбрать папку…",
                    detail: "Любая папка на Mac",
                    path: "",
                    symbol: "folder.badge.plus",
                    color: Color(red: 0.62, green: 0.67, blue: 0.78)
                ),
                isActive: false,
                isScanning: false
            ) {
                model.chooseFolder()
            }
            .padding(.top, 2)
        }
    }

    private var locations: [SidebarLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            SidebarLocation(title: "Домашняя папка", detail: "~", path: home,
                            symbol: "house.fill", color: Color(red: 0.44, green: 0.63, blue: 1.0)),
            SidebarLocation(title: "Программы", detail: "/Applications", path: "/Applications",
                            symbol: "square.grid.2x2.fill", color: Color(red: 0.68, green: 0.52, blue: 1.0)),
            SidebarLocation(title: "Загрузки", detail: "~/Downloads", path: home + "/Downloads",
                            symbol: "arrow.down.circle.fill", color: Color(red: 0.30, green: 0.80, blue: 0.90)),
            SidebarLocation(title: "Документы", detail: "~/Documents", path: home + "/Documents",
                            symbol: "doc.fill", color: Color(red: 0.42, green: 0.66, blue: 1.0)),
            SidebarLocation(title: "Рабочий стол", detail: "~/Desktop", path: home + "/Desktop",
                            symbol: "display", color: Color(red: 0.30, green: 0.82, blue: 0.68)),
            SidebarLocation(title: "Библиотека", detail: "~/Library", path: home + "/Library",
                            symbol: "books.vertical.fill", color: Color(red: 0.96, green: 0.68, blue: 0.30)),
            SidebarLocation(title: "Вся система", detail: "Macintosh HD", path: "/",
                            symbol: "internaldrive.fill", color: Color(red: 0.62, green: 0.67, blue: 0.78)),
        ]
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 4)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.isScanning ? Theme.warning : Theme.success)
                    .frame(width: 5, height: 5)
                Text(model.isScanning ? "Сканирование…" : "Свободно \(model.freeSpaceText)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                Menu {
                    Button("Выбрать папку…") { model.chooseFolder() }
                    Button("Полная картина диска…") { model.showDiskOverview() }
                    Button("Полный доступ к диску…") { model.openFullDiskAccessSettings() }
                    Divider()
                    Button("О программе DiskScope") {
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 22, height: 20)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Настройки")
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct SidebarLocation: Identifiable {
    let title: String
    let detail: String
    let path: String
    let symbol: String
    let color: Color

    var id: String { title + path }
}

private struct SidebarRow: View {
    let location: SidebarLocation
    let isActive: Bool
    let isScanning: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(location.color.opacity(isActive ? 0.30 : 0.16))
                    Image(systemName: location.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(location.color)
                }
                .frame(width: 23, height: 23)

                VStack(alignment: .leading, spacing: 0.5) {
                    Text(location.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(isActive ? 0.98 : 0.80))
                        .lineLimit(1)
                    Text(location.detail)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.white.opacity(isActive ? 0.5 : 0.3))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                if isScanning {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.6))
                } else if hovering || isActive {
                    Image(systemName: isActive ? "circle.fill" : "chevron.right")
                        .font(.system(size: isActive ? 4 : 7, weight: .bold))
                        .foregroundStyle(.white.opacity(isActive ? 0.55 : 0.3))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? Color.white.opacity(0.095)
                            : (hovering ? Color.white.opacity(0.055) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}
