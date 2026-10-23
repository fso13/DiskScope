import Foundation

public struct FolderBudget: Codable, Hashable, Identifiable, Sendable {
    public let path: String
    public var limitBytes: Int64

    public var id: String { path }

    public init(path: String, limitBytes: Int64) {
        self.path = FolderBudget.normalize(path)
        self.limitBytes = max(limitBytes, 0)
    }

    public static func normalize(_ path: String) -> String {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
            .expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}

public struct FolderBudgetStatus: Sendable, Identifiable {
    public let budget: FolderBudget
    public let currentBytes: Int64

    public var id: String { budget.path }

    public var fraction: Double {
        guard budget.limitBytes > 0 else { return 0 }
        return min(max(Double(currentBytes) / Double(budget.limitBytes), 0), 1)
    }

    public var rawFraction: Double {
        guard budget.limitBytes > 0 else { return 0 }
        return Double(currentBytes) / Double(budget.limitBytes)
    }

    public var exceeded: Bool {
        budget.limitBytes > 0 && currentBytes > budget.limitBytes
    }

    public var remainingBytes: Int64 {
        max(budget.limitBytes - currentBytes, 0)
    }

    public var overBy: Int64 {
        max(currentBytes - budget.limitBytes, 0)
    }

    public init(budget: FolderBudget, currentBytes: Int64) {
        self.budget = budget
        self.currentBytes = max(currentBytes, 0)
    }
}

public enum FolderBudgetEvaluator {
    public static func status(currentBytes: Int64, limitBytes: Int64, path: String) -> FolderBudgetStatus? {
        guard limitBytes > 0 else { return nil }
        return FolderBudgetStatus(
            budget: FolderBudget(path: path, limitBytes: limitBytes),
            currentBytes: currentBytes
        )
    }

    public static func matching(path: String, in budgets: [FolderBudget]) -> FolderBudget? {
        let normalized = FolderBudget.normalize(path)
        return budgets.first { $0.path == normalized && $0.limitBytes > 0 }
    }
}

public enum FolderBudgetStore {
    public static let defaultsKey = "app.settings.folderBudgets"

    public static func load(defaults: UserDefaults = .standard) -> [FolderBudget] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        let decoded = (try? JSONDecoder().decode([FolderBudget].self, from: data)) ?? []
        return decoded
            .filter { $0.limitBytes > 0 }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    @discardableResult
    public static func upsert(
        path: String,
        limitBytes: Int64,
        defaults: UserDefaults = .standard
    ) -> [FolderBudget] {
        var budgets = load(defaults: defaults)
        let normalized = FolderBudget.normalize(path)
        budgets.removeAll { $0.path == normalized }
        if limitBytes > 0 {
            budgets.append(FolderBudget(path: normalized, limitBytes: limitBytes))
        }
        return save(budgets, defaults: defaults)
    }

    @discardableResult
    public static func remove(path: String, defaults: UserDefaults = .standard) -> [FolderBudget] {
        let normalized = FolderBudget.normalize(path)
        return save(load(defaults: defaults).filter { $0.path != normalized }, defaults: defaults)
    }

    @discardableResult
    public static func save(
        _ budgets: [FolderBudget],
        defaults: UserDefaults = .standard
    ) -> [FolderBudget] {
        let normalized = Dictionary(
            budgets.filter { $0.limitBytes > 0 }.map {
                ($0.path, FolderBudget(path: $0.path, limitBytes: $0.limitBytes))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let sorted = normalized.values.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .folderBudgetsChanged, object: nil)
        return sorted
    }
}

public enum FolderBudgetNotifier {
    static let notifiedKey = "app.settings.folderBudgetNotified"

    /// Returns budgets that just crossed their limit; clears the flag when under.
    public static func newlyExceeded(
        _ statuses: [FolderBudgetStatus],
        defaults: UserDefaults = .standard
    ) -> [FolderBudgetStatus] {
        var notified = Set(defaults.stringArray(forKey: notifiedKey) ?? [])
        var result: [FolderBudgetStatus] = []
        for status in statuses {
            let token = "\(status.budget.path)|\(status.budget.limitBytes)"
            if status.exceeded {
                if notified.insert(token).inserted {
                    result.append(status)
                }
            } else {
                notified.remove(token)
            }
        }
        defaults.set(Array(notified).sorted(), forKey: notifiedKey)
        return result
    }
}

public extension Notification.Name {
    static let folderBudgetsChanged = Notification.Name("DiskScopeFolderBudgetsChanged")
}
