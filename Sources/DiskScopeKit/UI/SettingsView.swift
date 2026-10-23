import AppKit
import SwiftUI

public struct SettingsView: View {
    @AppStorage(AppSettingsKeys.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettingsKeys.confirmTrash) private var confirmTrash = true
    @AppStorage(AppSettingsKeys.language) private var language = AppLanguage.system.rawValue
    @AppStorage(AppSettingsKeys.menuBarMonitor) private var menuBarMonitor = false
    @AppStorage(AppSettingsKeys.menuBarDisplay) private var menuBarDisplay = MenuBarDisplayMode.free.rawValue
    @StateObject private var updater = UpdateChecker()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    appearanceSection
                    languageSection
                    menuBarSection
                    scanningSection
                    updatesSection
                    aboutSection
                    resetRow
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 680)
        .background(Theme.background)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .environment(\.locale, AppLanguage(rawValue: language)?.locale ?? Locale.current)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppMark(size: 34)
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("DiskScope")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.2)
                Text(L10n.isEnglish
                    ? "Settings · \(version) · build \(build)"
                    : "Настройки · \(version) · сборка \(build)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.75))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 17)
        .background(Theme.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var appearanceSection: some View {
        SettingsCard(title: "Внешний вид", symbol: "circle.lefthalf.filled") {
            Picker("Оформление", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(LocalizedStringKey(option.title)).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Применяется к главному окну и настройкам. Системная тема следует оформлению macOS.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languageSection: some View {
        SettingsCard(title: "Язык", symbol: "globe") {
            Picker("Язык интерфейса", selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(LocalizedStringKey(option.title)).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Системный следует языку macOS. Английский включает англоязычный интерфейс и форматы.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var menuBarSection: some View {
        SettingsCard(title: "Меню-бар", symbol: "menubar.rectangle") {
            Toggle("Показывать свободное место", isOn: $menuBarMonitor)
                .toggleStyle(.switch)
                .font(.system(size: 11.5, weight: .medium))

            Picker("Отображение", selection: $menuBarDisplay) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.title)).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!menuBarMonitor)

            Text("Иконка остаётся в строке меню, даже когда окно DiskScope закрыто. Клик открывает меню со свободным местом и быстрыми действиями.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: menuBarMonitor) { _, _ in
            NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
        }
        .onChange(of: menuBarDisplay) { _, _ in
            NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
        }
    }

    private var scanningSection: some View {
        SettingsCard(title: "Сканирование", symbol: "internaldrive") {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Повторный анализ не запускается")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("Если сканирование уже идёт, новые запросы игнорируются. Остановить его можно кнопкой «Остановить».")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("ВКЛ")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.success.opacity(0.1), in: Capsule())
            }

            Divider().overlay(Theme.border)

            VStack(alignment: .leading, spacing: 6) {
                Text("Подтверждение перед Корзиной")
                    .font(.system(size: 11.5, weight: .medium))
                Picker("Подтверждение перед Корзиной", selection: $confirmTrash) {
                    Text("Спрашивать").tag(true)
                    Text("Без подтверждения").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Text("При отключении объекты сразу отправляются в Корзину без дополнительного подтверждения.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var updatesSection: some View {
        SettingsCard(title: "Обновления", symbol: "arrow.triangle.2.circlepath") {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(updateTitle))
                        .font(.system(size: 11.5, weight: .medium))
                    Text(LocalizedStringKey(updateDetail))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                updateAction
            }

            Text("Сеть используется только для этого запроса; файлы и результаты сканирования не отправляются.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        switch updater.state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 86)
        case .available(let release):
            Button("Скачать") {
                NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .failed:
            Button("Повторить") {
                updater.check(currentVersion: version)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        default:
            Button("Проверить") {
                updater.check(currentVersion: version)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var updateTitle: String {
        switch updater.state {
        case .idle: return "Проверка обновлений"
        case .checking: return "Проверяем обновления…"
        case .upToDate: return "Установлена последняя версия"
        case .available(let release): return "Доступна версия \(release.version)"
        case .failed: return "Не удалось проверить"
        }
    }

    private var updateDetail: String {
        switch updater.state {
        case .idle:
            return L10n.isEnglish
                ? "Current version \(version). Checks run only when you click Check."
                : "Текущая версия \(version). Запрос выполняется только по кнопке."
        case .checking:
            return L10n.t("Запрашиваем GitHub Releases…")
        case .upToDate(let current):
            return L10n.isEnglish
                ? "DiskScope \(current) is up to date."
                : "DiskScope \(current) — обновлений нет."
        case .available:
            return L10n.isEnglish
                ? "Current version \(version). Download the DMG and replace the app."
                : "Текущая версия \(version). Скачайте DMG и замените приложение."
        case .failed(let message):
            return message
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "О программе", symbol: "info.circle") {
            SettingsRow(label: "Версия", value: version)
            SettingsRow(label: "Сборка", value: build)
            SettingsRow(label: "Система", value: operatingSystem)
            SettingsRow(label: "Архитектура", value: architecture)

            Divider().overlay(Theme.border)

            HStack(spacing: 8) {
                Link(destination: URL(string: "https://fso13.github.io/DiskScope/")!) {
                    Label("Документация", systemImage: "book")
                }
                Link(destination: URL(string: "https://github.com/fso13/DiskScope")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 10.5, weight: .medium))

            Text("Сканирование и файлы остаются локальными. Сеть используется только для проверки обновлений.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
    }

    private var resetRow: some View {
        HStack(spacing: 10) {
            Text("Настройки хранятся локально.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Button("Сбросить настройки") {
                appearance = AppAppearance.system.rawValue
                confirmTrash = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 2)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.1"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var operatingSystem: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }

    private var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(LocalizedStringKey(title))
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.7)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

private struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}
