import Foundation

public enum SearchKind: String, CaseIterable, Identifiable, Sendable {
    case any
    case files
    case folders
    case packages

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: return "Всё"
        case .files: return "Файлы"
        case .folders: return "Папки"
        case .packages: return "Пакеты"
        }
    }
}

public enum SearchDateRange: String, CaseIterable, Identifiable, Sendable {
    case any
    case month
    case year
    case older

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: return "Любая дата"
        case .month: return "За месяц"
        case .year: return "За год"
        case .older: return "Старше года"
        }
    }
}

public enum SearchSort: String, CaseIterable, Identifiable, Sendable {
    case size
    case name
    case modified

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .size: return "По размеру"
        case .name: return "По имени"
        case .modified: return "По дате"
        }
    }
}

public struct SearchQuery: Sendable {
    public var text: String
    public var minimumSize: Int64
    public var category: FileCategory?
    public var kind: SearchKind
    public var dateRange: SearchDateRange
    public var sort: SearchSort
    public var limit: Int
    public var now: Date

    public init(
        text: String,
        minimumSize: Int64 = 0,
        category: FileCategory? = nil,
        kind: SearchKind = .any,
        dateRange: SearchDateRange = .any,
        sort: SearchSort = .size,
        limit: Int = 500,
        now: Date = Date()
    ) {
        self.text = text
        self.minimumSize = max(minimumSize, 0)
        self.category = category
        self.kind = kind
        self.dateRange = dateRange
        self.sort = sort
        self.limit = max(limit, 1)
        self.now = now
    }
}

public struct SearchHit: Identifiable, Sendable {
    public let index: Int32
    public let name: String
    public let path: String
    public let relativePath: String
    public let size: Int64
    public let category: FileCategory
    public let isHardLink: Bool
    public let kind: NodeKind
    public let modified: Date?
    public let itemCount: Int

    public var id: Int32 { index }
}

public struct SearchResults: Sendable {
    public let hits: [SearchHit]
    public let total: Int

    public var truncated: Bool { total > hits.count }
}

/// A compact, lazily built name index over a scan tree.
public final class ScanSearchIndex: @unchecked Sendable {
    private struct Entry {
        let index: Int32
        let foldedName: String
    }

    private let tree: ScanTree
    private let entries: [Entry]
    private let locale = Locale(identifier: "ru_RU")

    public init(tree: ScanTree) {
        self.tree = tree
        var entries: [Entry] = []
        var stack: [Int32] = [0]
        while let index = stack.popLast() {
            let node = tree.node(index)
            switch node.nodeKind {
            case .aggregate, .symlink:
                continue
            case .package:
                entries.append(Entry(
                    index: index,
                    foldedName: Self.fold(tree.name(of: index), locale: locale)
                ))
            case .directory:
                if index != 0 {
                    entries.append(Entry(
                        index: index,
                        foldedName: Self.fold(tree.name(of: index), locale: locale)
                    ))
                }
                for child in tree.children(of: index) {
                    stack.append(child)
                }
            case .file:
                entries.append(Entry(
                    index: index,
                    foldedName: Self.fold(tree.name(of: index), locale: locale)
                ))
            }
        }
        self.entries = entries
    }

    public var treeIdentifier: ObjectIdentifier { ObjectIdentifier(tree) }

    public func search(_ query: SearchQuery) -> SearchResults {
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchResults(hits: [], total: 0)
        }
        let foldedQuery = Self.fold(trimmed, locale: locale)
        guard !foldedQuery.isEmpty else {
            return SearchResults(hits: [], total: 0)
        }
        let wantsPath = trimmed.contains("/")
        let today = ScanNode.dayNumber(seconds: Int64(query.now.timeIntervalSince1970))

        var matched: [Int32] = []
        for entry in entries where matchesFilters(entry.index, query: query, today: today) {
            let nameMatches = entry.foldedName.contains(foldedQuery)
            let pathMatches = !nameMatches
                && wantsPath
                && Self.fold(tree.relativePath(of: entry.index), locale: locale).contains(foldedQuery)
            guard nameMatches || pathMatches else { continue }
            matched.append(entry.index)
        }

        matched.sort { isOrderedBefore($0, $1, sort: query.sort) }
        let hits = matched.prefix(query.limit).map(makeHit)
        return SearchResults(hits: Array(hits), total: matched.count)
    }

    // MARK: - Filters

    private func matchesFilters(_ index: Int32, query: SearchQuery, today: Int32) -> Bool {
        let node = tree.node(index)
        if node.size < query.minimumSize { return false }
        switch query.kind {
        case .any: break
        case .files: guard node.nodeKind == .file else { return false }
        case .folders: guard node.nodeKind == .directory else { return false }
        case .packages: guard node.nodeKind == .package else { return false }
        }
        if let category = query.category, tree.category(of: index) != category {
            return false
        }
        if query.dateRange != .any {
            guard let day = tree.modifiedDay(of: index) else { return false }
            let age = Int(today) - Int(day)
            switch query.dateRange {
            case .any: break
            case .month: guard age <= 30 else { return false }
            case .year: guard age <= 365 else { return false }
            case .older: guard age > 365 else { return false }
            }
        }
        return true
    }

    // MARK: - Ordering

    private func isOrderedBefore(_ lhs: Int32, _ rhs: Int32, sort: SearchSort) -> Bool {
        switch sort {
        case .size:
            if tree.node(lhs).size != tree.node(rhs).size {
                return tree.node(lhs).size > tree.node(rhs).size
            }
            return name(lhs).localizedStandardCompare(name(rhs)) == .orderedAscending
        case .name:
            return name(lhs).localizedStandardCompare(name(rhs)) == .orderedAscending
        case .modified:
            switch (tree.modified(of: lhs), tree.modified(of: rhs)) {
            case let (left?, right?):
                if left != right { return left > right }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return tree.node(lhs).size > tree.node(rhs).size
        }
    }

    // MARK: - Hits

    private func makeHit(_ index: Int32) -> SearchHit {
        let node = tree.node(index)
        let raw = tree.name(of: index)
        return SearchHit(
            index: index,
            name: raw.isEmpty ? "Без имени" : raw,
            path: tree.path(of: index),
            relativePath: tree.relativePath(of: index),
            size: node.size,
            category: tree.category(of: index),
            isHardLink: node.isHardLink,
            kind: node.nodeKind,
            modified: tree.modified(of: index),
            itemCount: Int(node.itemCount)
        )
    }

    private func name(_ index: Int32) -> String {
        let name = tree.name(of: index)
        return name.isEmpty ? "Без имени" : name
    }

    private static func fold(_ value: String, locale: Locale) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        )
    }
}
