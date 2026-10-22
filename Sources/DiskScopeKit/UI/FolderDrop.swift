import SwiftUI
import UniformTypeIdentifiers

enum FolderDrop {
    /// Returns the folder to scan for a dropped URL: a directory itself, or the
    /// parent folder when a file was dropped.
    static func folderURL(for url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }
}

struct FolderDropTarget: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handle(providers)
                return true
            }
            .overlay {
                if isTargeted {
                    highlight
                }
            }
    }

    private var highlight: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 9) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Theme.accent)
                Text("Отпустите папку")
                    .font(.system(size: 15, weight: .semibold))
                Text("DiskScope начнёт новый скан")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func handle(_ providers: [NSItemProvider]) {
        guard providers.count == 1, let provider = providers.first else {
            model.showToast("Перетащите одну папку", symbol: "exclamationmark.triangle")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let nsurl = item as? NSURL {
                url = nsurl as URL
            } else if let value = item as? URL {
                url = value
            }

            guard let url, let folder = FolderDrop.folderURL(for: url) else {
                DispatchQueue.main.async {
                    model.showToast("Это не папка", symbol: "exclamationmark.triangle")
                }
                return
            }

            DispatchQueue.main.async {
                guard !model.isScanning else {
                    model.showToast("Сканирование уже идёт", symbol: "hourglass")
                    return
                }
                model.scan(path: folder.path)
            }
        }
    }
}

extension View {
    func folderDropTarget() -> some View {
        modifier(FolderDropTarget())
    }
}
