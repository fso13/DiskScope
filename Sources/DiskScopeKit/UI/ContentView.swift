import AppKit
import QuickLook
import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppSettingsKeys.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettingsKeys.language) private var language = AppLanguage.system.rawValue

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            WindowTitleBar()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: Theme.sidebarWidth)
                main
                if model.showInspector, model.phase == .ready {
                    InspectorView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(backgroundLayer)
        .background(WindowConfigurator())
        .frame(minWidth: 1180, minHeight: 760)
        .folderDropTarget()
        .overlay(alignment: .bottom) { toastLayer }
        .alert("Переместить в Корзину?", isPresented: $model.trash.showSelectionConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("В Корзину", role: .destructive) { model.trashOperations.confirmSelection() }
        } message: {
            Text(trashMessage)
        }
        .alert("Очистить выбранное?", isPresented: $model.cleanup.showConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) { model.cleanupOperations.confirm() }
        } message: {
            Text(model.cleanup.confirmationMessage)
        }
        .alert("Ошибка", isPresented: errorBinding) {
            Button("OK") { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $model.showPermissionSheet) {
            PermissionSheet(samples: model.tree?.report.sampleSkippedPaths ?? [])
        }
        .sheet(isPresented: $model.showCollection) {
            CollectionView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.search.show) {
            GlobalSearchView(search: model.search)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.history.show) {
            HistoryView()
                .environmentObject(model)
        }
        .onAppear { model.browser.refreshVolumes() }
        .quickLookPreview($model.inspector.quickLookURL)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .environment(\.locale, AppLanguage(rawValue: language)?.locale ?? Locale.current)
    }

    private var trashMessage: String {
        let count = model.browser.selectedCount
        let size = ByteFormat.string(model.browser.selectedSize)
        return "\(Plural.items(count)) · \(size). Объекты можно восстановить из Корзины."
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.dismissError() } }
        )
    }

    private var backgroundLayer: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.accent.opacity(0.055), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 780
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var main: some View {
        switch model.phase {
        case .welcome:
            WelcomeView()
        case .scanning:
            ScanningView()
        case .failed(let message):
            FailureView(message: message)
        case .ready:
            ReadyView()
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = model.toast {
            ToastView(toast: toast) { model.dismissToast() }
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct ReadyView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()

            if model.browser.hasPermissionIssues && model.tab != .media {
                PermissionBanner(
                    count: model.tree?.report.skippedItems ?? 0,
                    onDetails: { model.showPermissionSheet = true },
                    onSettings: { model.browser.openFullDiskAccessSettings() }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            Group {
                switch model.tab {
                case .map:
                    MapView()
                case .largest:
                    LargestFilesView()
                case .types:
                    TypesView()
                case .media:
                    MediaView(media: model.media)
                case .cleanup:
                    CleanupView()
                case .disk:
                    DiskOverviewView()
                case .duplicates:
                    DuplicatesView()
                case .similar:
                    SimilarImagesView()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.tab != .media && model.tab != .disk
                && model.tab != .duplicates && model.tab != .similar {
                StatusBar()
            }
        }
    }
}

struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.success)
                .frame(width: 5, height: 5)
            if let tree = model.tree {
                Text("\(L10n.t(model.browser.rootDisplayName)) · \(ByteFormat.string(tree.totalSize)) · \(Plural.files(tree.totalFiles))")
                Text("·")
                Text(L10n.isEnglish
                    ? "scanned in \(ByteFormat.duration(tree.report.duration))"
                    : "скан за \(ByteFormat.duration(tree.report.duration))")
                if tree.report.skippedMounts > 0 {
                    Text(L10n.isEnglish
                        ? "· \(tree.report.skippedMounts) volumes skipped"
                        : "· \(tree.report.skippedMounts) томов пропущено")
                }
            } else {
                Text("Готово")
            }
            if model.collectionCount > 0 {
                Text("·")
                Button {
                    model.showCollection = true
                } label: {
                    Text(L10n.isEnglish
                        ? "Collection: \(model.collectionSummary)"
                        : "Коллекция: \(model.collectionSummary)")
                }
                .buttonStyle(.plain)
                .help("Открыть коллекцию (⌘6)")
            }
            Spacer()
            Text(L10n.isEnglish ? "Free \(model.browser.freeSpaceText)" : "Свободно \(model.browser.freeSpaceText)")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(Theme.card.opacity(0.35))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

struct FailureView: View {
    @EnvironmentObject private var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.danger.opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Theme.danger)
            }
            Text("Не удалось просканировать")
                .font(AppFont.title(22))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                AccentButton(title: "Повторить", symbol: "arrow.clockwise") {
                    model.rescan()
                }
                GhostButton(title: "Выбрать другую папку", symbol: "folder", tint: Theme.accent) {
                    model.chooseFolder()
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct PermissionSheet: View {
    @EnvironmentObject private var model: AppModel
    let samples: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.warning.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ограниченный доступ")
                        .font(AppFont.title(18))
                    Text("macOS не показывает содержимое защищённых папок без разрешения.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "Чтобы DiskScope видел все файлы, добавьте приложение в «Конфиденциальность и безопасность → Полный доступ к диску» "
                    + "и перезапустите сканирование."
            )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !samples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Нет доступа, например, к:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(samples, id: \.self) { path in
                                Text(path)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 130)
                    .padding(10)
                    .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 9))
                }
            }

            Spacer(minLength: 0)

            HStack {
                GhostButton(title: "Закрыть", action: { dismiss() })
                Spacer()
                AccentButton(title: "Открыть настройки", symbol: "gearshape.fill") {
                    model.browser.openFullDiskAccessSettings()
                    dismiss()
                }
            }
        }
        .padding(22)
        .frame(width: 520, height: 380)
        .background(Theme.background)
    }
}
