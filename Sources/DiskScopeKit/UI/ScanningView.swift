import SwiftUI

struct ScanningView: View {
    @EnvironmentObject private var model: AppModel

    private var progress: ScanProgress? { model.progress }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)

            ScanRing(progress: progress)

            VStack(spacing: 6) {
                Text("Сканируем диск")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.3)
                Text(progress?.currentPath ?? "Готовимся…")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 560)
                    .help(progress?.currentPath ?? "")
            }

            HStack(spacing: 8) {
                StatPill(symbol: "square.stack.3d.up", text: "\(ByteFormat.count(progress?.entries ?? 0)) объектов")
                StatPill(symbol: "doc.on.doc", text: Plural.files(progress?.files ?? 0))
                StatPill(symbol: "speedometer", text: "\(ByteFormat.count(Int(progress?.entriesPerSecond ?? 0))) об/с")
                StatPill(symbol: "clock", text: ByteFormat.duration(progress?.elapsed ?? 0))
            }

            Button {
                model.cancelScan()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Остановить")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Text("Сканирование можно остановить в любой момент — данные на диске не изменятся.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct ScanRing: View {
    let progress: ScanProgress?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.2) / 2.2 * 360

            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.08), lineWidth: 8)
                    .frame(width: 182, height: 182)

                Circle()
                    .trim(from: 0.02, to: 0.72)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Theme.accent.opacity(0.05),
                                Theme.accent,
                                Theme.accentDeep,
                                Theme.accent.opacity(0.05),
                            ],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 182, height: 182)
                    .rotationEffect(.degrees(angle))

                Circle()
                    .fill(Theme.card)
                    .frame(width: 146, height: 146)
                    .shadow(color: .black.opacity(0.10), radius: 12, y: 4)

                VStack(spacing: 3) {
                    Text(ByteFormat.string(progress?.bytes ?? 0))
                        .font(AppFont.number(25))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("НАЙДЕНО")
                        .font(.system(size: 7.5, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 182, height: 182)
    }
}
