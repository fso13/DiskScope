import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                hero
                quickCards
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Можно перетащить папку прямо в окно")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.tertiary)
                auxiliaryActions
                volumeCard
                steps
                accessHint
                footer
            }
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .padding(.bottom, 28)
        }
    }

    private var hero: some View {
        VStack(spacing: 13) {
            AppMark(size: 84)
                .shadow(color: Theme.accent.opacity(0.35), radius: 22, y: 10)
                .padding(.bottom, 2)

            Text("DiskScope")
                .font(.system(size: 40, weight: .bold))
                .tracking(-1.2)

            Text("Найдите, что на самом деле занимает место на диске")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                feature("bolt.fill", "Быстрый скан")
                feature("square.grid.2x2.fill", "Тепловая карта")
                feature("trash.fill", "Очистка в Корзину")
                feature("lock.fill", "Только локально")
            }
            .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var quickCards: some View {
        HStack(spacing: 12) {
            QuickStartCard(
                symbol: "house.fill",
                color: Color(red: 0.44, green: 0.63, blue: 1.0),
                title: "Домашняя папка",
                subtitle: "Документы, загрузки, кэши и библиотеки"
            ) {
                model.scanHome()
            }

            QuickStartCard(
                symbol: "square.grid.2x2.fill",
                color: Color(red: 0.68, green: 0.52, blue: 1.0),
                title: "Программы",
                subtitle: "Приложения и все их ресурсы"
            ) {
                model.scan(path: "/Applications")
            }

            QuickStartCard(
                symbol: "internaldrive.fill",
                color: Color(red: 0.30, green: 0.74, blue: 0.86),
                title: "Вся система",
                subtitle: "Система, пользователи и данные"
            ) {
                model.scan(path: "/")
            }
        }
    }

    private var auxiliaryActions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            AccentButton(title: "Выбрать папку…", symbol: "folder.badge.plus") {
                model.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: .command)

            if let last = model.lastScanPath, !last.isEmpty {
                Button {
                    model.scan(path: last)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Продолжить: \(abbreviate(last))")
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.subtleFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(last)
            }

            Spacer(minLength: 0)
        }
    }

    private func abbreviate(_ path: String) -> String {
        let home = model.homePath
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private var volumeCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(model.internalVolume?.name ?? "Macintosh HD")
                        .font(.system(size: 13, weight: .semibold))
                    Text("APFS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.subtleFill, in: Capsule())
                }

                if let volume = model.internalVolume {
                    ProgressBar(fraction: volume.usedFraction, height: 7)
                    HStack(spacing: 5) {
                        Text("Занято \(ByteFormat.string(volume.usedBytes))")
                        Text("·")
                        Text("Свободно \(ByteFormat.string(volume.freeBytes))")
                        Text("из \(ByteFormat.string(volume.totalBytes))")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 10)

            if let volume = model.internalVolume {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormat.percent(volume.usedBytes, of: volume.totalBytes))
                        .font(AppFont.number(21))
                        .monospacedDigit()
                    Text("занято")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if let volume = model.internalVolume { model.scanVolume(volume) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .bold))
                    Text("Анализировать")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.accent.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .cardSurface()
    }

    private var steps: some View {
        HStack(spacing: 10) {
            step(number: "1", title: "Выберите папку", text: "Домашняя папка, программы или весь диск")
            step(number: "2", title: "Изучите карту", text: "Чем больше прямоугольник — тем больше места")
            step(number: "3", title: "Освободите место", text: "Удаляйте лишнее в Корзину из таблицы")
        }
    }

    private func step(number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(width: 21, height: 21)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var accessHint: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.warning)
            Text("Для полной картины дайте DiskScope «Полный доступ к диску» в настройках macOS.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Button("Открыть настройки") {
                model.openFullDiskAccessSettings()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Theme.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.18), lineWidth: 1)
        )
    }

    private var footer: some View {
        Text("DiskScope 1.0 · сканирует локально и ничего не отправляет в сеть")
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
    }
}

private struct QuickStartCard: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(color.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0.45)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? color.opacity(0.35) : Theme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.10 : 0.05), radius: hovering ? 14 : 10, y: hovering ? 6 : 4)
            .scaleEffect(hovering ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.16)) { hovering = value }
        }
        .help("Сканировать: \(title)")
    }
}
