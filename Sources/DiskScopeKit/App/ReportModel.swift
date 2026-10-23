import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// Owns report export: save panel, report options, filename and writing.
@MainActor
public final class ReportModel: ObservableObject {
    private var treeProvider: () -> ScanTree? = { nil }
    private var currentIndexProvider: () -> Int32 = { 0 }
    private var searchProvider: () -> String = { "" }
    private var categoryProvider: () -> FileCategory? = { nil }
    private var currentNameProvider: () -> String = { "" }
    private var rootDisplayNameProvider: () -> String = { "DiskScope" }
    private var toastHandler: (String, String) -> Void = { _, _ in }
    private var errorHandler: (String) -> Void = { _ in }
    private let versionProvider: () -> String

    public init(versionProvider: @escaping () -> String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }) {
        self.versionProvider = versionProvider
    }

    func attach(
        treeProvider: @escaping () -> ScanTree?,
        currentIndexProvider: @escaping () -> Int32,
        searchProvider: @escaping () -> String,
        categoryProvider: @escaping () -> FileCategory?,
        currentNameProvider: @escaping () -> String,
        rootDisplayNameProvider: @escaping () -> String,
        toast: @escaping (String, String) -> Void,
        error: @escaping (String) -> Void
    ) {
        self.treeProvider = treeProvider
        self.currentIndexProvider = currentIndexProvider
        self.searchProvider = searchProvider
        self.categoryProvider = categoryProvider
        self.currentNameProvider = currentNameProvider
        self.rootDisplayNameProvider = rootDisplayNameProvider
        self.toastHandler = toast
        self.errorHandler = error
    }

    public var canExportReport: Bool { treeProvider() != nil }

    /// Shows a save panel and writes a CSV or HTML report of the current scan.
    public func exportReport(format: ReportFormat = .csv, scope: ReportScope = .currentFolder) {
        guard let tree = treeProvider() else { return }

        let panel = NSSavePanel()
        panel.title = "Экспортировать отчёт"
        panel.message = "CSV или HTML. Отчёт строится по текущему скану и видимым фильтрам."
        panel.prompt = "Экспортировать"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .html]
        panel.nameFieldStringValue = defaultReportFilename(format: format, scope: scope)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let options = options(format: format, scope: scope)
        let rootIndex = currentIndexProvider()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let text: String
                switch format {
                case .csv:
                    text = ReportExporter.makeCSV(tree: tree, rootIndex: rootIndex, options: options)
                case .html:
                    text = ReportExporter.makeHTML(tree: tree, rootIndex: rootIndex, options: options)
                }
                try ReportExporter.write(text, to: url)
                DispatchQueue.main.async {
                    self?.toastHandler("Отчёт сохранён: \(url.lastPathComponent)", "doc.text.fill")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorHandler("Не удалось сохранить отчёт: \(error.localizedDescription)")
                }
            }
        }
    }

    var appVersion: String { versionProvider() }

    func options(
        format: ReportFormat,
        scope: ReportScope,
        generatedAt: Date = Date()
    ) -> ReportOptions {
        ReportOptions(
            format: format,
            scope: scope,
            search: searchProvider(),
            category: categoryProvider(),
            generatedAt: generatedAt,
            appVersion: appVersion
        )
    }

    func defaultReportFilename(format: ReportFormat, scope: ReportScope) -> String {
        let raw = scope == .currentFolder ? currentNameProvider() : rootDisplayNameProvider()
        var safe = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if safe.isEmpty { safe = "DiskScope" }
        return "DiskScope-\(safe).\(format.fileExtension)"
    }
}
