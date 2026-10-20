import AppKit
import DiskScopeKit
import SwiftUI

// Renders the real SwiftUI interface into PNG files so the design can be
// reviewed without a screen-recording permission. Usage:
//   swift run DiskScopeSnapshots <output-dir> [scan-path]

@main
struct SnapshotMain {
    @MainActor
    static func main() async {
        let arguments = CommandLine.arguments
        let outputDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "snapshots")
        let scanPath = arguments.count > 2 ? arguments[2] : "/Applications"

        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        NSApplication.shared.setActivationPolicy(.accessory)

        FileHandle.standardError.write(Data("Scanning \(scanPath)…\n".utf8))
        let scanner = DiskScanner(options: .balanced)
        let tree: ScanTree
        do {
            tree = try scanner.scan(path: scanPath)
        } catch {
            FileHandle.standardError.write(Data("Scan failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }

        let size = CGSize(width: 1440, height: 900)
        let renderer = SnapshotRenderer(size: size, outputDirectory: outputDirectory)
        renderer.renderAll(tree: tree)
        renderer.wait()
        FileHandle.standardError.write(Data("Snapshots written to \(outputDirectory.path)\n".utf8))
    }
}

@MainActor
final class SnapshotRenderer {
    private let size: CGSize
    private let outputDirectory: URL
    private var window: NSWindow?

    init(size: CGSize, outputDirectory: URL) {
        self.size = size
        self.outputDirectory = outputDirectory
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func wait() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    func renderAll(tree: ScanTree) {
        let model = AppModel()

        model.loadPreview(tree: tree)
        model.tab = .map
        render(model: model, named: "01-map-light", dark: false)
        render(model: model, named: "02-map-dark", dark: true)

        model.tab = .largest
        render(model: model, named: "03-largest", dark: false)

        model.tab = .types
        render(model: model, named: "04-types", dark: false)

        model.tab = .map
        let deepFolder = findNode(in: tree, components: ["Xcode.app", "Contents", "Developer", "Platforms"])
            ?? firstPlausibleFolder(in: tree)
        if let deepFolder {
            model.previewNavigate(to: deepFolder)
            render(model: model, named: "05-map-folder", dark: false)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let mediaFiles: [MediaFile] = [
            MediaFile(path: home.appendingPathComponent("Pictures/Отпуск 2025/IMG_2041.HEIC").path,
                      relativePath: "Отпуск 2025/IMG_2041.HEIC",
                      sourceRoot: home.appendingPathComponent("Pictures").path,
                      size: 5_400_000, kind: .image, modified: Date().addingTimeInterval(-86_400 * 3)),
            MediaFile(path: home.appendingPathComponent("Pictures/Отпуск 2025/IMG_2039.JPG").path,
                      relativePath: "Отпуск 2025/IMG_2039.JPG",
                      sourceRoot: home.appendingPathComponent("Pictures").path,
                      size: 4_800_000, kind: .image, modified: Date().addingTimeInterval(-86_400 * 4)),
            MediaFile(path: home.appendingPathComponent("Pictures/Семейный альбом/IMG_1987.PNG").path,
                      relativePath: "Семейный альбом/IMG_1987.PNG",
                      sourceRoot: home.appendingPathComponent("Pictures").path,
                      size: 3_200_000, kind: .image, modified: Date().addingTimeInterval(-86_400 * 11)),
            MediaFile(path: home.appendingPathComponent("Music/track-01.mp3").path,
                      relativePath: "track-01.mp3",
                      sourceRoot: home.appendingPathComponent("Music").path,
                      size: 9_100_000, kind: .audio, modified: Date().addingTimeInterval(-86_400 * 30)),
            MediaFile(path: home.appendingPathComponent("Movies/clip.mov").path,
                      relativePath: "clip.mov",
                      sourceRoot: home.appendingPathComponent("Movies").path,
                      size: 142_000_000, kind: .video, modified: Date().addingTimeInterval(-86_400 * 60)),
            MediaFile(path: home.appendingPathComponent("Documents/report.pdf").path,
                      relativePath: "report.pdf",
                      sourceRoot: home.appendingPathComponent("Documents").path,
                      size: 2_400_000, kind: .pdf, modified: Date().addingTimeInterval(-86_400 * 8)),
            MediaFile(path: home.appendingPathComponent("Documents/letter.docx").path,
                      relativePath: "letter.docx",
                      sourceRoot: home.appendingPathComponent("Documents").path,
                      size: 180_000, kind: .doc, modified: Date().addingTimeInterval(-86_400 * 15)),
            MediaFile(path: home.appendingPathComponent("Documents/sheet.xlsx").path,
                      relativePath: "sheet.xlsx",
                      sourceRoot: home.appendingPathComponent("Documents").path,
                      size: 96_000, kind: .document, modified: Date().addingTimeInterval(-86_400 * 20)),
        ]
        model.media.loadPreview(
            sources: [
                home.appendingPathComponent("Pictures"),
                home.appendingPathComponent("Documents"),
                home.appendingPathComponent("Music"),
            ],
            types: [.image, .audio, .video, .document],
            files: mediaFiles,
            destination: home.appendingPathComponent("Downloads/Медиа"),
            selected: Set(mediaFiles.prefix(3).map(\.id))
        )
        model.tab = .media
        render(model: model, named: "10-media-light", dark: false)
        render(model: model, named: "11-media-dark", dark: true)

        model.previewWelcome()
        render(model: model, named: "06-welcome", dark: false)
        render(model: model, named: "07-welcome-dark", dark: true)

        model.previewScanning(
            path: model.homePath + "/Library/Application Support",
            progress: ScanProgress(
                entries: 2_148_932,
                files: 1_842_010,
                directories: 306_922,
                bytes: 128_465_233_920,
                currentPath: "~/Library/Application Support/Cursor/User/globalStorage",
                elapsed: 47.3
            )
        )
        render(model: model, named: "08-scanning", dark: false)

        renderSettings(named: "12-settings-light", dark: false)
        renderSettings(named: "13-settings-dark", dark: true)
    }

    private func renderSettings(named name: String, dark: Bool) {
        UserDefaults.standard.set("system", forKey: "app.settings.appearance")
        UserDefaults.standard.set(true, forKey: "app.settings.confirmTrash")
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApplication.shared.appearance = appearance

        let settingsSize = CGSize(width: 560, height: 600)
        let root = SettingsView()
            .frame(width: settingsSize.width, height: settingsSize.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: settingsSize)
        hosting.appearance = appearance

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.backgroundColor = .black
        window.isOpaque = true
        window.contentView = hosting
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -24000, y: -24000))
        window.orderFrontRegardless()

        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write(Data("No bitmap for \(name)\n".utf8))
            window.orderOut(nil)
            return
        }
        representation.size = settingsSize
        hosting.cacheDisplay(in: hosting.bounds, to: representation)

        if let data = representation.representation(using: .png, properties: [:]) {
            let url = outputDirectory.appendingPathComponent(name + ".png")
            do {
                try data.write(to: url)
                FileHandle.standardError.write(Data("  wrote \(url.lastPathComponent)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("  failed to write \(name): \(error)\n".utf8))
            }
        }
        window.orderOut(nil)
    }

    private func findNode(in tree: ScanTree, components: [String]) -> Int32? {
        var current: Int32 = 0
        for component in components {
            guard let next = tree.children(of: current).first(where: { tree.name(of: $0) == component }) else {
                return nil
            }
            current = next
        }
        return current
    }

    private func firstPlausibleFolder(in tree: ScanTree) -> Int32? {
        let children = tree.children(of: 0)
            .filter { tree.node($0).nodeKind == .directory && tree.node($0).size > 100 * 1024 * 1024 }
            .sorted { tree.node($0).size > tree.node($1).size }
        return children.first
    }

    private func dumpScrollViews(_ view: NSView, depth: Int) {
        let name = String(describing: type(of: view))
        if name == "NSScroller" || name.contains("Scroll") || name.contains("Table") {
            let frame = view.convert(view.bounds, to: nil)
            print(String(repeating: "  ", count: depth) + name + " frame=\(NSStringFromRect(frame))")
            if let scrollView = view as? NSScrollView {
                print(String(repeating: "  ", count: depth) + "  scroller style=\(scrollView.scrollerStyle.rawValue) hasVertical=\(scrollView.hasVerticalScroller) vframe=\(scrollView.verticalScroller.map { NSStringFromRect($0.convert($0.bounds, to: nil)) } ?? "nil")")
            }
        }
        for subview in view.subviews {
            dumpScrollViews(subview, depth: depth + 1)
        }
    }

    private func render(model: AppModel, named name: String, dark: Bool) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApplication.shared.appearance = appearance

        let root = ContentView()
            .environmentObject(model)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = appearance

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.backgroundColor = .black
        window.isOpaque = true
        window.contentView = hosting
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -24000, y: -24000))
        window.orderFrontRegardless()
        self.window = window

        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        hosting.layoutSubtreeIfNeeded()

        if ProcessInfo.processInfo.environment["DISKSCOPE_DEBUG_VIEWS"] != nil, name.contains("map-light") {
            dumpScrollViews(hosting, depth: 0)
        }

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write(Data("No bitmap for \(name)\n".utf8))
            window.orderOut(nil)
            return
        }
        representation.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: representation)

        if let data = representation.representation(using: .png, properties: [:]) {
            let url = outputDirectory.appendingPathComponent(name + ".png")
            do {
                try data.write(to: url)
                FileHandle.standardError.write(Data("  wrote \(url.lastPathComponent)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("  failed to write \(name): \(error)\n".utf8))
            }
        }
        window.orderOut(nil)
        self.window = nil
    }
}
