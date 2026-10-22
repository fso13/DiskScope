import AppIntents
import DiskScopeKit
import Foundation
import UniformTypeIdentifiers

struct FolderScanEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Folder Scan")
    static var defaultQuery = FolderScanQuery()

    let id: String
    let summary: FolderScanSummary

    @Property(title: "Path")
    var path: String

    @Property(title: "Total bytes")
    var totalBytes: Int

    @Property(title: "Files")
    var files: Int

    @Property(title: "Folders")
    var folders: Int

    @Property(title: "Within budget")
    var withinBudget: Bool?

    @Property(title: "Exceeded by (bytes)")
    var exceededBy: Int?

    init(summary: FolderScanSummary, withinBudget: Bool? = nil, exceededBy: Int64? = nil) {
        self.id = summary.path
        self.summary = summary
        self.path = summary.path
        self.totalBytes = Int(summary.totalBytes)
        self.files = summary.files
        self.folders = summary.folders
        self.withinBudget = withinBudget
        self.exceededBy = exceededBy.map(Int.init)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(summary.name)",
            subtitle: "\(summary.totalHuman) · \(summary.files) files"
        )
    }
}

struct FolderScanQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FolderScanEntity] { [] }
    func suggestedEntities() async throws -> [FolderScanEntity] { [] }
}

struct ScanFolderIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan folder with DiskScope"
    static var description = IntentDescription(
        "Scans a folder locally and returns its size, file count and duration."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Folder")
    var folder: IntentFile

    @Parameter(title: "Budget (bytes)")
    var budgetBytes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Scan \(\.$folder)") {
            \.$budgetBytes
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<FolderScanEntity> & ProvidesDialog {
        let summary = try await Self.scan(folder)
        let budget = budgetBytes.map { CLIBudget(limitBytes: Int64($0), totalBytes: summary.totalBytes) }
        let entity = FolderScanEntity(
            summary: summary,
            withinBudget: budget?.withinBudget,
            exceededBy: budget?.exceededBy
        )
        var text = "\(summary.name): \(summary.totalHuman), \(summary.files) files"
        if let budget {
            text += budget.withinBudget
                ? " — within budget"
                : " — over budget by \(ByteFormat.string(budget.exceededBy))"
        }
        return .result(value: entity, dialog: IntentDialog(stringLiteral: text))
    }

    static func scan(_ folder: IntentFile) async throws -> FolderScanSummary {
        guard let url = folder.fileURL else {
            throw FolderScanError.invalidFolder
        }
        return try await Task.detached(priority: .userInitiated) {
            try FolderScanSummary.scan(url: url)
        }.value
    }
}

struct CheckDiskBudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Check folder budget"
    static var description = IntentDescription(
        "Scans a folder and compares its size with a byte budget."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Folder")
    var folder: IntentFile

    @Parameter(title: "Budget (bytes)")
    var budgetBytes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$folder) against \(\.$budgetBytes)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<FolderScanEntity> & ProvidesDialog {
        let summary = try await ScanFolderIntent.scan(folder)
        let budget = CLIBudget(limitBytes: Int64(budgetBytes), totalBytes: summary.totalBytes)
        let entity = FolderScanEntity(
            summary: summary,
            withinBudget: budget.withinBudget,
            exceededBy: budget.exceededBy
        )
        let text = budget.withinBudget
            ? "Within budget: \(summary.totalHuman) of \(ByteFormat.string(budget.limitBytes))"
            : "Over budget by \(ByteFormat.string(budget.exceededBy))"
        return .result(value: entity, dialog: IntentDialog(stringLiteral: text))
    }
}

enum FolderScanError: Error, CustomLocalizedStringResourceConvertible {
    case invalidFolder

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidFolder: return "Choose a folder to scan."
        }
    }
}

struct DiskScopeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanFolderIntent(),
            phrases: [
                "Scan a folder with \(.applicationName)",
                "Scan \(\.$folder) with \(.applicationName)",
            ],
            shortTitle: "Scan folder",
            systemImageName: "internaldrive"
        )
        AppShortcut(
            intent: CheckDiskBudgetIntent(),
            phrases: [
                "Check a folder budget with \(.applicationName)",
            ],
            shortTitle: "Check budget",
            systemImageName: "gauge.with.dots.needle.bottom.50percent"
        )
    }
}
