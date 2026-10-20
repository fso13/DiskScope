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
