import Foundation

// MARK: - Risk and disposition

/// How risky it is to remove a suggestion. Drives ordering and default selection.
public enum CleanupRisk: Int, CaseIterable, Identifiable, Sendable, Comparable {
    case safe = 0
    case review = 1
    case expert = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .safe: return "Безопасно"
        case .review: return "Проверить"
        case .expert: return "Осторожно"
        }
    }

    public var symbolName: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .review: return "exclamationmark.triangle.fill"
        case .expert: return "exclamationmark.octagon.fill"
        }
    }

    public var explanation: String {
        switch self {
        case .safe: return "Приложения или система пересоздадут это автоматически."
        case .review: return "Удаление освободит место, но проверьте содержимое."
        case .expert: return "Может сломать сборку или настройки. Удаляйте осознанно."
        }
    }

    public static func < (lhs: CleanupRisk, rhs: CleanupRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the cleanup screen should do with a selected suggestion.
public enum CleanupDisposition: String, Sendable {
    case trash
    case deletePermanently
}

// MARK: - Environment

/// Values rules need besides the scan tree. Rules never touch the filesystem.
public struct CleanupEnvironment: Sendable {
    public let homePath: String
    public let now: Date
    public let runningBundleIdentifiers: Set<String>

    public init(homePath: String, now: Date = Date(), runningBundleIdentifiers: Set<String> = []) {
        var normalized = homePath
        while normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        self.homePath = normalized
        self.now = now
        self.runningBundleIdentifiers = runningBundleIdentifiers
    }

    public static func current(runningBundleIdentifiers: Set<String> = []) -> CleanupEnvironment {
        CleanupEnvironment(
            homePath: FileManager.default.homeDirectoryForCurrentUser.path,
            runningBundleIdentifiers: runningBundleIdentifiers
        )
    }
}

// MARK: - Suggestions and rules

public struct CleanupSuggestion: Identifiable, Hashable, Sendable {
    public let id: String
    public let ruleID: String
    public let title: String
    public let nodeIndex: Int32
    public let name: String
    public let path: String
    public let relativePath: String
    public let size: Int64
    public let itemCount: Int
    public let risk: CleanupRisk
    public let reason: String
    public let isDirectory: Bool
    public let disposition: CleanupDisposition
    public let isSelectedByDefault: Bool

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: CleanupSuggestion, rhs: CleanupSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}

struct CleanupMatch: Sendable {
    let nodeIndex: Int32
    let size: Int64
    let itemCount: Int
}

/// A declarative cleanup rule. Matching is a pure function of the scan tree.
public struct CleanupRule: Identifiable, @unchecked Sendable {
    typealias Matcher = (ScanTree, CleanupEnvironment) -> [CleanupMatch]

    public let id: String
    public let title: String
    public let risk: CleanupRisk
    public let explanation: String
    public let examplePath: String
    public let disposition: CleanupDisposition
    public let defaultSelected: Bool?

    let matcher: Matcher

    init(
        id: String,
        title: String,
        risk: CleanupRisk,
        explanation: String,
        examplePath: String,
        disposition: CleanupDisposition = .trash,
        defaultSelected: Bool? = nil,
        matcher: @escaping Matcher
    ) {
        self.id = id
        self.title = title
        self.risk = risk
        self.explanation = explanation
        self.examplePath = examplePath
        self.disposition = disposition
        self.defaultSelected = defaultSelected
        self.matcher = matcher
    }
}

// MARK: - Catalog

public enum CleanupCatalog {
    public static let rules: [CleanupRule] = [
        trashRule,
        derivedDataRule,
        archivesRule,
        deviceSupportRule,
        downloadsRule,
        iosBackupsRule,
        dockerDiskImageRule,
        gradleCacheRule,
        mavenCacheRule,
        npmCacheRule,
        homebrewCacheRule,
        simulatorCachesRule,
        libraryCachesRule,
        xcodeUserDataRule,
        nodeModulesRule,
    ]

    // MARK: Rules

    private static var trashRule: CleanupRule {
        directoryRule(
            id: "trash",
            title: "Корзина",
            relativePath: ".Trash",
            risk: .safe,
            explanation: "Файлы уже удалены. Очистка освобождает место безвозвратно.",
            examplePath: "~/.Trash",
            disposition: .deletePermanently
        )
    }

    private static var derivedDataRule: CleanupRule {
        directoryRule(
            id: "xcode-derived-data",
            title: "DerivedData Xcode",
            relativePath: "Library/Developer/Xcode/DerivedData",
            risk: .safe,
            explanation: "Индексы и промежуточные сборки. Xcode пересоздаст их при следующей сборке.",
            examplePath: "~/Library/Developer/Xcode/DerivedData"
        )
    }

    private static var archivesRule: CleanupRule {
        childrenRule(
            id: "xcode-archives",
            title: "Старые архивы Xcode",
            parents: ["Library/Developer/Xcode/Archives"],
            risk: .safe,
            explanation: "Архивы сборок старше 180 дней. Их можно пересобрать из исходников.",
            examplePath: "~/Library/Developer/Xcode/Archives/2025-01-01",
            minimumAgeDays: 180
        )
    }

    private static var deviceSupportRule: CleanupRule {
        childrenRule(
            id: "xcode-device-support",
            title: "Символы устройств Xcode",
            parents: [
                "Library/Developer/Xcode/iOS DeviceSupport",
                "Library/Developer/Xcode/watchOS DeviceSupport",
                "Library/Developer/Xcode/tvOS DeviceSupport",
                "Library/Developer/Xcode/visionOS DeviceSupport",
            ],
            risk: .safe,
            explanation: "Отладочные символы для версий ОС. Xcode скачает их снова "
                + "при подключении устройства.",
            examplePath: "~/Library/Developer/Xcode/iOS DeviceSupport/18.0"
        )
    }

    private static var downloadsRule: CleanupRule {
        childrenRule(
            id: "downloads-installers",
            title: "Старые установщики",
            parents: ["Downloads"],
            risk: .safe,
            explanation: "Установщики старше 30 дней. После установки они обычно не нужны.",
            examplePath: "~/Downloads/App.dmg",
            extensions: ["dmg", "pkg", "zip", "xip", "iso"],
            minimumAgeDays: 30
        )
    }

    private static var iosBackupsRule: CleanupRule {
        childrenRule(
            id: "ios-backups",
            title: "Старые бэкапы iPhone",
            parents: ["Library/Application Support/MobileSync/Backup"],
            risk: .review,
            explanation: "Локальные резервные копии старше 180 дней. "
                + "Проверьте, что они не единственные.",
            examplePath: "~/Library/Application Support/MobileSync/Backup/<UDID>",
            minimumAgeDays: 180
        )
    }

    private static var dockerDiskImageRule: CleanupRule {
        rule(
            id: "docker-disk-image",
            title: "Образ Docker",
            risk: .review,
            explanation: "Диск с образами и контейнерами Docker. Удаление освободит "
                + "место, но данные будут потеряны.",
            examplePath: "~/Library/Containers/com.docker.docker/Data/vms/0/data/"
                + "Docker.raw"
        ) { tree, environment in
            guard !environment.runningBundleIdentifiers.contains("com.docker.docker") else { return [] }
            let path = environment.homePath
                + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
            guard let index = CleanupPathResolver(tree: tree).index(forAbsolute: path) else { return [] }
            let node = tree.node(index)
            guard node.nodeKind == .file, node.size > 0 else { return [] }
            return [CleanupMatch(nodeIndex: index, size: node.size, itemCount: 1)]
        }
    }

    private static var gradleCacheRule: CleanupRule {
        directoryRule(
            id: "gradle-cache",
            title: "Кэш Gradle",
            relativePath: ".gradle/caches",
            risk: .review,
            explanation: "Кэш зависимостей Gradle. Скачается заново при следующей сборке.",
            examplePath: "~/.gradle/caches"
        )
    }

    private static var mavenCacheRule: CleanupRule {
        directoryRule(
            id: "maven-cache",
            title: "Кэш Maven",
            relativePath: ".m2/repository",
            risk: .review,
            explanation: "Локальный репозиторий Maven. Зависимости скачаются снова при сборке.",
            examplePath: "~/.m2/repository"
        )
    }

    private static var npmCacheRule: CleanupRule {
        directoryRule(
            id: "npm-cache",
            title: "Кэш npm",
            relativePath: ".npm/_cacache",
            risk: .review,
            explanation: "Кэш пакетов npm. Восстановится при следующей установке зависимостей.",
            examplePath: "~/.npm/_cacache"
        )
    }

    private static var homebrewCacheRule: CleanupRule {
        directoryRule(
            id: "homebrew-cache",
            title: "Кэш Homebrew",
            relativePath: "Library/Caches/Homebrew",
            risk: .review,
            explanation: "Скачанные бутылки и исходники Homebrew. При необходимости скачаются снова.",
            examplePath: "~/Library/Caches/Homebrew"
        )
    }

    private static var simulatorCachesRule: CleanupRule {
        directoryRule(
            id: "core-simulator-caches",
            title: "Кэш симулятора",
            relativePath: "Library/Developer/CoreSimulator/Caches",
            risk: .safe,
            explanation: "Временные файлы CoreSimulator. Пересоздаются при запуске симулятора.",
            examplePath: "~/Library/Developer/CoreSimulator/Caches"
        )
    }

    private static var libraryCachesRule: CleanupRule {
        childrenRule(
            id: "library-caches",
            title: "Кэши приложений",
            parents: ["Library/Caches"],
            risk: .safe,
            explanation: "Кэш приложения. Оно пересоздаст его; активное приложение "
                + "может временно работать медленнее.",
            examplePath: "~/Library/Caches/com.example.app",
            minimumSize: 50 * 1024 * 1024,
            excludedNames: ["Homebrew"],
            maxMatches: 100
        )
    }

    private static var xcodeUserDataRule: CleanupRule {
        directoryRule(
            id: "xcode-user-data",
            title: "Пользовательские данные Xcode",
            relativePath: "Library/Developer/Xcode/UserData",
            risk: .expert,
            explanation: "Шаблоны, брейкпоинты и настройки Xcode. Удаление сбросит персонализацию.",
            examplePath: "~/Library/Developer/Xcode/UserData"
        )
    }

    private static var nodeModulesRule: CleanupRule {
        rule(
            id: "node-modules",
            title: "node_modules",
            risk: .expert,
            explanation: "Зависимости проекта. Восстановимы через npm/yarn/pnpm "
                + "install; до этого сборка не работает.",
            examplePath: "~/Projects/app/node_modules",
            defaultSelected: false
        ) { tree, _ in
            var found: [CleanupMatch] = []
            var stack: [Int32] = [0]
            while let index = stack.popLast() {
                let node = tree.node(index)
                guard node.nodeKind == .directory else { continue }
                if index != 0, tree.name(of: index) == "node_modules" {
                    if node.size > 0 {
                        found.append(CleanupMatch(
                            nodeIndex: index,
                            size: node.size,
                            itemCount: Int(node.itemCount)
                        ))
                    }
                    continue
                }
                for child in tree.children(of: index) where tree.node(child).nodeKind == .directory {
                    stack.append(child)
                }
            }
            found.sort { $0.size > $1.size }
            return Array(found.prefix(50))
        }
    }

    // MARK: Factories

    private static func rule(
        id: String,
        title: String,
        risk: CleanupRisk,
        explanation: String,
        examplePath: String,
        disposition: CleanupDisposition = .trash,
        defaultSelected: Bool? = nil,
        matcher: @escaping CleanupRule.Matcher
    ) -> CleanupRule {
        CleanupRule(
            id: id,
            title: title,
            risk: risk,
            explanation: explanation,
            examplePath: examplePath,
            disposition: disposition,
            defaultSelected: defaultSelected,
            matcher: matcher
        )
    }

    private static func directoryRule(
        id: String,
        title: String,
        relativePath: String,
        risk: CleanupRisk,
        explanation: String,
        examplePath: String,
        minimumSize: Int64 = 1,
        disposition: CleanupDisposition = .trash,
        defaultSelected: Bool? = nil
    ) -> CleanupRule {
        rule(
            id: id,
            title: title,
            risk: risk,
            explanation: explanation,
            examplePath: examplePath,
            disposition: disposition,
            defaultSelected: defaultSelected
        ) { tree, environment in
            let path = environment.homePath + "/" + relativePath
            guard let index = CleanupPathResolver(tree: tree).index(forAbsolute: path) else { return [] }
            let node = tree.node(index)
            guard node.nodeKind.isContainer, node.size >= minimumSize else { return [] }
            return [CleanupMatch(nodeIndex: index, size: node.size, itemCount: Int(node.itemCount))]
        }
    }

    private static func childrenRule(
        id: String,
        title: String,
        parents: [String],
        risk: CleanupRisk,
        explanation: String,
        examplePath: String,
        extensions: Set<String>? = nil,
        minimumSize: Int64 = 1,
        minimumAgeDays: Int = 0,
        excludedNames: Set<String> = [],
        maxMatches: Int = 200
    ) -> CleanupRule {
        rule(
            id: id,
            title: title,
            risk: risk,
            explanation: explanation,
            examplePath: examplePath
        ) { tree, environment in
            let resolver = CleanupPathResolver(tree: tree)
            var matches: [CleanupMatch] = []
            for parent in parents {
                let parentPath = environment.homePath + "/" + parent
                guard let parentIndex = resolver.index(forAbsolute: parentPath) else { continue }
                for child in tree.children(of: parentIndex) {
                    if matches.count >= maxMatches { break }
                    if excludedNames.contains(tree.name(of: child)) { continue }
                    let node = tree.node(child)
                    guard node.nodeKind == .file || node.nodeKind == .directory || node.nodeKind == .package
                    else { continue }
                    guard node.size >= minimumSize else { continue }
                    if let extensions {
                        guard node.nodeKind == .file,
                              extensions.contains(tree.fileExtension(of: child)) else { continue }
                    }
                    if minimumAgeDays > 0 {
                        guard let age = CleanupAdvisor.daysSinceModification(
                            child,
                            tree: tree,
                            now: environment.now
                        ), age >= minimumAgeDays else { continue }
                    }
                    matches.append(CleanupMatch(
                        nodeIndex: child,
                        size: node.size,
                        itemCount: Int(node.itemCount)
                    ))
                }
            }
            return matches
        }
    }
}

// MARK: - Advisor

public enum CleanupAdvisor {
    /// Matches the catalog against a scan tree. Pure: no filesystem access.
    public static func recommend(
        tree: ScanTree,
        environment: CleanupEnvironment,
        rules: [CleanupRule] = CleanupCatalog.rules,
        limit: Int = 500
    ) -> [CleanupSuggestion] {
        guard limit > 0 else { return [] }

        var collected: [CleanupSuggestion] = []
        for rule in rules {
            for match in rule.matcher(tree, environment) where match.nodeIndex > 0 {
                guard Int(match.nodeIndex) < tree.count, !tree.isDeleted(match.nodeIndex) else { continue }
                let node = tree.node(match.nodeIndex)
                guard node.nodeKind != .aggregate else { continue }
                collected.append(CleanupSuggestion(
                    id: "\(rule.id):\(match.nodeIndex)",
                    ruleID: rule.id,
                    title: rule.title,
                    nodeIndex: match.nodeIndex,
                    name: tree.name(of: match.nodeIndex),
                    path: tree.path(of: match.nodeIndex),
                    relativePath: tree.relativePath(of: match.nodeIndex),
                    size: match.size,
                    itemCount: match.itemCount,
                    risk: rule.risk,
                    reason: rule.explanation,
                    isDirectory: node.nodeKind.isContainer,
                    disposition: rule.disposition,
                    isSelectedByDefault: rule.defaultSelected ?? (rule.risk == .safe)
                ))
            }
        }

        let unique = removeNested(collected)
        let sorted = unique.sorted { left, right in
            if left.risk != right.risk { return left.risk < right.risk }
            if left.size != right.size { return left.size > right.size }
            return left.path.localizedStandardCompare(right.path) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }

    /// Days between the node's modification day and `now`, or nil when unknown.
    static func daysSinceModification(_ index: Int32, tree: ScanTree, now: Date) -> Int? {
        guard let day = tree.modifiedDay(of: index) else { return nil }
        let today = ScanNode.dayNumber(seconds: Int64(now.timeIntervalSince1970))
        return Int(today) - Int(day)
    }

    /// Drops identical paths and suggestions nested inside another suggestion.
    private static func removeNested(_ suggestions: [CleanupSuggestion]) -> [CleanupSuggestion] {
        var seen = Set<String>()
        var unique: [CleanupSuggestion] = []
        for suggestion in suggestions where seen.insert(suggestion.path).inserted {
            unique.append(suggestion)
        }

        let byDepth = unique.sorted { $0.path.count < $1.path.count }
        var accepted: [CleanupSuggestion] = []
        var acceptedPaths: [String] = []
        for suggestion in byDepth {
            if acceptedPaths.contains(where: { suggestion.path.hasPrefix($0 + "/") }) { continue }
            accepted.append(suggestion)
            acceptedPaths.append(suggestion.path)
        }
        return accepted
    }
}

// MARK: - Path resolution

struct CleanupPathResolver {
    private let tree: ScanTree
    private let prefix: String

    init(tree: ScanTree) {
        self.tree = tree
        self.prefix = tree.rootPath == "/" ? "/" : tree.rootPath + "/"
    }

    /// Resolves an absolute path inside the scan tree. Returns nil outside the root.
    func index(forAbsolute path: String) -> Int32? {
        if path == tree.rootPath { return 0 }
        guard path.hasPrefix(prefix) else { return nil }
        var current: Int32 = 0
        for component in path.dropFirst(prefix.count).split(separator: "/") where !component.isEmpty {
            guard let next = tree.children(of: current).first(where: {
                tree.name(of: $0) == String(component)
            }) else {
                return nil
            }
            current = next
        }
        return current
    }
}
