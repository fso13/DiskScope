import Foundation

/// Export format for a disk report.
public enum ReportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case html

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .csv: return "CSV"
        case .html: return "HTML"
        }
    }

    public var fileExtension: String { rawValue }
}

/// What part of the scan a report covers.
public enum ReportScope: String, CaseIterable, Identifiable, Sendable {
    case currentFolder
    case wholeScan

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .currentFolder: return "Текущая папка"
        case .wholeScan: return "Весь скан"
        }
    }
}

public struct ReportOptions: Sendable {
    public var format: ReportFormat
    public var scope: ReportScope
    public var search: String
    public var category: FileCategory?
    public var limit: Int
    public var generatedAt: Date
    public var appVersion: String

    public init(
        format: ReportFormat = .csv,
        scope: ReportScope = .currentFolder,
        search: String = "",
        category: FileCategory? = nil,
        limit: Int = 10_000,
        generatedAt: Date = Date(),
        appVersion: String = "dev"
    ) {
        self.format = format
        self.scope = scope
        self.search = search
        self.category = category
        self.limit = max(limit, 1)
        self.generatedAt = generatedAt
        self.appVersion = appVersion
    }
}

struct ReportRow {
    let index: Int32
    let name: String
    let path: String
    let relativePath: String
    let size: Int64
    let fraction: Double
    let category: FileCategory
    let kind: String
    let modified: Date?
    let itemCount: Int
}

/// Builds a self-contained CSV or HTML report from a scan tree.
public enum ReportExporter {
    public static func makeCSV(
        tree: ScanTree,
        rootIndex: Int32,
        options: ReportOptions
    ) -> String {
        let rows = makeRows(tree: tree, rootIndex: rootIndex, options: options)
        let dayFormatter = csvDayFormatter()
        var lines = [
            "\u{FEFF}Путь;Имя;Размер (байт);Доля (%);Категория;Тип;Изменён;Элементов",
        ]
        for row in rows {
            let fields = [
                row.path,
                row.name,
                String(row.size),
                String(format: "%.2f", row.fraction * 100),
                row.category.title,
                row.kind,
                row.modified.map { dayFormatter.string(from: $0) } ?? "",
                String(row.itemCount),
            ]
            lines.append(fields.map(csvField).joined(separator: ";"))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func makeHTML(
        tree: ScanTree,
        rootIndex: Int32,
        options: ReportOptions
    ) -> String {
        let rows = makeRows(tree: tree, rootIndex: rootIndex, options: options)
        let top = Array(rows.prefix(100))
        let node = tree.node(rootIndex)
        let totalSize = options.scope == .currentFolder ? node.size : tree.totalSize
        let itemCount = options.scope == .currentFolder ? Int(node.itemCount) : tree.totalFiles
        let folderCount = options.scope == .currentFolder
            ? directoryCount(tree: tree, rootIndex: rootIndex)
            : tree.directoryCount()
        let stats = categoryStats(tree: tree, rootIndex: rootIndex, scope: options.scope)
        let scopePath = tree.path(of: rootIndex)
        let generated = htmlDate(options.generatedAt)
        let query = options.search.trimmingCharacters(in: .whitespacesAndNewlines)

        var filters: [String] = []
        if !query.isEmpty {
            filters.append("Поиск: «\(query)»")
        }
        if let category = options.category {
            filters.append("Категория: \(category.title)")
        }
        let filterText = filters.isEmpty ? "Без фильтров" : filters.joined(separator: " · ")

        var html = """
        <!doctype html>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="DiskScope \(escapeHTML(options.appVersion))">
        <title>DiskScope — отчёт об анализе диска</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <main class="report">
        <header>
        <div class="eyebrow">DiskScope · локальный анализ</div>
        <h1>Отчёт об анализе диска</h1>
        <p class="scope">\(escapeHTML(scopePath))</p>
        <p class="meta">Сформирован \(escapeHTML(generated)) · Версия \(escapeHTML(options.appVersion)) · \(escapeHTML(filterText))</p>
        </header>

        <section class="stats">
        <div class="stat"><span>Занято</span><strong>\(escapeHTML(ByteFormat.string(totalSize)))</strong></div>
        <div class="stat"><span>Объектов</span><strong>\(escapeHTML(Plural.items(itemCount)))</strong></div>
        <div class="stat"><span>Папок</span><strong>\(escapeHTML(Plural.folders(folderCount)))</strong></div>
        <div class="stat"><span>Длительность скана</span><strong>\(escapeHTML(ByteFormat.duration(tree.report.duration)))</strong></div>
        <div class="stat"><span>Пропущено</span><strong>\(tree.report.skippedItems)</strong></div>
        </section>

        """

        if !stats.isEmpty {
            html += """
            <section>
            <h2>Категории</h2>
            <table>
            <thead><tr>
            <th>Категория</th><th class="right">Размер</th><th class="right">Доля</th><th class="right">Объектов</th>
            </tr></thead>
            <tbody>
            """
            for stat in stats {
                html += """
                <tr>
                <td>\(escapeHTML(stat.category.title))</td>
                <td class="right">\(escapeHTML(ByteFormat.string(stat.size)))</td>
                <td class="right">\(escapeHTML(ByteFormat.percent(stat.size, of: max(totalSize, 1))))</td>
                <td class="right">\(stat.count)</td>
                </tr>
                """
            }
            html += """
            </tbody>
            </table>
            </section>

            """
        }

        html += """
        <section>
        <h2>Крупнейшие объекты</h2>
        <p class="hint">\(top.count == 100 ? "Первые 100 объектов по размеру." : "Все найденные объекты по размеру.")</p>
        """
        if top.isEmpty {
            html += """
            <p class="empty">Нет объектов, подходящих под выбранные фильтры.</p>
            """
        } else {
            html += """
            <table>
            <thead><tr>
            <th>Имя</th><th>Где</th><th class="right">Размер</th><th class="right">Доля</th><th>Тип</th><th>Изменён</th>
            </tr></thead>
            <tbody>
            """
            for row in top {
                let location = row.relativePath.isEmpty ? row.path : row.relativePath
                html += """
                <tr>
                <td><strong>\(escapeHTML(row.name))</strong><div class="mono">\(escapeHTML(row.path))</div></td>
                <td class="mono">\(escapeHTML(location))</td>
                <td class="right">\(escapeHTML(ByteFormat.string(row.size)))</td>
                <td class="right">\(escapeHTML(ByteFormat.percent(row.size, of: max(totalSize, 1))))</td>
                <td>\(escapeHTML(row.kind))</td>
                <td>\(escapeHTML(row.modified.map(htmlDay) ?? "—"))</td>
                </tr>
                """
            }
            html += """
            </tbody>
            </table>
            """
        }
        html += """
        </section>

        <footer>
        Отчёт сформирован локально приложением DiskScope. Файлы и результаты не покидали Mac.
        </footer>
        </main>
        </body>
        </html>
        """
        return html
    }

    public static func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    // MARK: - Rows

    static func makeRows(
        tree: ScanTree,
        rootIndex: Int32,
        options: ReportOptions
    ) -> [ReportRow] {
        guard rootIndex >= 0, Int(rootIndex) < tree.count else { return [] }
        let root = tree.node(rootIndex)
        let baseSize = max(root.size, 1)
        let query = options.search.trimmingCharacters(in: .whitespacesAndNewlines)

        let indices: [Int32]
        switch options.scope {
        case .currentFolder:
            indices = tree.children(of: rootIndex).sorted {
                tree.node($0).size > tree.node($1).size
            }
        case .wholeScan:
            indices = tree.largestItems(limit: max(options.limit * 3, 4_000))
        }

        var rows: [ReportRow] = []
        for index in indices {
            if rows.count >= options.limit { break }
            let node = tree.node(index)
            if options.scope == .wholeScan, node.nodeKind == .aggregate { continue }
            if let category = options.category, tree.category(of: index) != category { continue }
            if !query.isEmpty {
                let name = tree.name(of: index)
                let relative = tree.relativePath(of: index)
                guard name.localizedCaseInsensitiveContains(query)
                    || relative.localizedCaseInsensitiveContains(query) else { continue }
            }
            let rawName = tree.name(of: index)
            let name = node.nodeKind == .aggregate
                ? Plural.smallFiles(Int(node.itemCount))
                : (rawName.isEmpty ? "Без имени" : rawName)
            rows.append(ReportRow(
                index: index,
                name: name,
                path: tree.path(of: index),
                relativePath: tree.relativePath(of: index),
                size: node.size,
                fraction: Double(node.size) / Double(baseSize),
                category: tree.category(of: index),
                kind: kindName(for: node.nodeKind),
                modified: tree.modified(of: index),
                itemCount: Int(node.itemCount)
            ))
        }
        return rows
    }

    // MARK: - Helpers

    private static func kindName(for kind: NodeKind) -> String {
        switch kind {
        case .directory: return "Папка"
        case .file: return "Файл"
        case .package: return "Пакет"
        case .symlink: return "Ссылка"
        case .aggregate: return "Мелкие файлы"
        }
    }

    static func categoryStats(
        tree: ScanTree,
        rootIndex: Int32,
        scope: ReportScope
    ) -> [CategoryStat] {
        if scope == .wholeScan {
            return tree.categoryStats()
        }

        var sizes = [Int64](repeating: 0, count: FileCategory.allCases.count)
        var counts = [Int](repeating: 0, count: FileCategory.allCases.count)
        var stack: [Int32] = tree.children(of: rootIndex)
        while let index = stack.popLast() {
            let node = tree.node(index)
            switch node.nodeKind {
            case .package:
                sizes[FileCategory.app.rawValue] += node.size
                counts[FileCategory.app.rawValue] += 1
            case .file:
                let category = tree.category(of: index)
                sizes[category.rawValue] += node.size
                counts[category.rawValue] += 1
            case .aggregate:
                sizes[FileCategory.other.rawValue] += node.size
                counts[FileCategory.other.rawValue] += Int(node.itemCount)
            case .directory:
                if node.childrenCount > 0 {
                    let start = Int(node.childrenStart)
                    let end = start + Int(node.childrenCount)
                    for child in start..<end where !tree.isDeleted(Int32(child)) {
                        stack.append(Int32(child))
                    }
                }
            case .symlink:
                break
            }
        }
        return FileCategory.allCases
            .map { CategoryStat(category: $0, size: sizes[$0.rawValue], count: counts[$0.rawValue]) }
            .filter { $0.size > 0 || $0.count > 0 } // swiftlint:disable:this empty_count
            .sorted { $0.size > $1.size }
    }

    static func directoryCount(tree: ScanTree, rootIndex: Int32) -> Int {
        var count = 0
        var stack: [Int32] = [rootIndex]
        while let index = stack.popLast() {
            let node = tree.node(index)
            guard node.nodeKind.isContainer else { continue }
            count += 1
            if node.childrenCount > 0 {
                let start = Int(node.childrenStart)
                let end = start + Int(node.childrenCount)
                for child in start..<end where !tree.isDeleted(Int32(child)) {
                    stack.append(Int32(child))
                }
            }
        }
        return count
    }

    private static func csvField(_ value: String) -> String {
        var value = value
        // Prevent spreadsheet formula injection from file names in a local report.
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }
        guard value.contains(";") || value.contains("\"")
            || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func csvDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func htmlDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy, HH:mm"
        return formatter.string(from: date)
    }

    private static func htmlDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private static let css = """
    :root {
      color-scheme: light dark;
      --bg: #f5f6fa;
      --card: #ffffff;
      --text: #171a23;
      --muted: #687083;
      --border: #e4e6ef;
      --accent: #5b6cf9;
      --accent-soft: #eef0ff;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0b0d12;
        --card: #141821;
        --text: #eef1f8;
        --muted: #9aa2b5;
        --border: #252a36;
        --accent: #8b98ff;
        --accent-soft: #1d2236;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.5;
    }
    .report { max-width: 1120px; margin: 0 auto; padding: 42px 28px 64px; }
    header { margin-bottom: 28px; }
    .eyebrow {
      color: var(--accent);
      font-size: 11px;
      font-weight: 700;
      letter-spacing: .12em;
      text-transform: uppercase;
    }
    h1 { font-size: 32px; letter-spacing: -.03em; margin: 6px 0 8px; }
    h2 { font-size: 17px; margin: 0 0 10px; letter-spacing: -.01em; }
    .scope { color: var(--muted); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; margin: 0 0 4px; word-break: break-all; }
    .meta { color: var(--muted); font-size: 12px; margin: 0; }
    section {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 18px;
      margin: 14px 0;
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 12px;
      padding: 16px;
    }
    .stat { padding: 10px 12px; background: var(--accent-soft); border-radius: 10px; }
    .stat span { display: block; color: var(--muted); font-size: 10px; text-transform: uppercase; letter-spacing: .06em; }
    .stat strong { display: block; font-size: 18px; margin-top: 3px; letter-spacing: -.01em; }
    table { width: 100%; border-collapse: collapse; font-size: 12.5px; }
    th { text-align: left; color: var(--muted); font-size: 10px; text-transform: uppercase;
      letter-spacing: .06em; padding: 8px 10px; border-bottom: 1px solid var(--border); }
    td { padding: 9px 10px; border-top: 1px solid var(--border); vertical-align: top; }
    tr:first-child td { border-top: 0; }
    .right { text-align: right; white-space: nowrap; }
    .mono { color: var(--muted); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 10.5px; word-break: break-all; }
    .hint { color: var(--muted); font-size: 11.5px; margin: -2px 0 12px; }
    .empty { color: var(--muted); font-size: 13px; padding: 12px 0; }
    footer { color: var(--muted); font-size: 11px; text-align: center; margin-top: 26px; }
    @media (max-width: 640px) {
      .report { padding: 26px 14px 40px; }
      h1 { font-size: 26px; }
      th:nth-child(4), td:nth-child(4), th:nth-child(6), td:nth-child(6) { display: none; }
    }
    """
}
