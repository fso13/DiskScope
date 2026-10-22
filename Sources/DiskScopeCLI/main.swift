import Foundation
import DiskScopeKit

// Headless companion for benchmarks, smoke tests and CI size budgets.
// Usage: diskscope-cli [--json] [--budget BYTES] [--limit N] [--min-size BYTES] [--output FILE] <path>

var path: String?
var limit = 15
var minimumFileSize: Int64 = 64 * 1024
var quiet = false
var json = false
var budgetBytes: Int64?
var outputPath: String?

func usage() {
    print("""
    usage: diskscope-cli [options] <path>

      --json              machine-readable report on stdout
      --budget SIZE       fail with exit 3 when total exceeds SIZE (e.g. 10GB)
      --limit N           number of top/largest entries (default 15)
      --min-size BYTES    aggregate files below this size (default 65536)
      --output FILE       write the report to FILE instead of stdout
      --quiet             disable progress output
      --version           print the CLI version
      -h, --help          show this help
    """)
}

var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let argument = iterator.next() {
    switch argument {
    case "--limit":
        if let value = iterator.next(), let parsed = Int(value), parsed >= 0 {
            limit = parsed
        } else {
            FileHandle.standardError.write(Data("error: --limit expects a non-negative integer\n".utf8))
            exit(1)
        }
    case "--min-size":
        if let value = iterator.next(), let parsed = Int64(value), parsed >= 0 {
            minimumFileSize = parsed
        } else {
            FileHandle.standardError.write(Data("error: --min-size expects bytes\n".utf8))
            exit(1)
        }
    case "--budget":
        guard let value = iterator.next(), let parsed = ByteSize.parse(value) else {
            FileHandle.standardError.write(Data("error: --budget expects a size, e.g. 10GB\n".utf8))
            exit(1)
        }
        budgetBytes = parsed
    case "--output":
        guard let value = iterator.next() else {
            FileHandle.standardError.write(Data("error: --output expects a path\n".utf8))
            exit(1)
        }
        outputPath = value
    case "--json":
        json = true
    case "--quiet":
        quiet = true
    case "--version":
        print("diskscope-cli 1.2")
        exit(0)
    case "--help", "-h":
        usage()
        exit(0)
    default:
        if argument.hasPrefix("-") {
            FileHandle.standardError.write(Data("error: unknown option \(argument)\n".utf8))
            usage()
            exit(1)
        }
        path = argument
    }
}

guard let target = path else {
    usage()
    exit(1)
}
if json { quiet = true }
if outputPath != nil, !json {
    FileHandle.standardError.write(Data("error: --output requires --json\n".utf8))
    exit(1)
}

let options = ScanOptions(minimumFileSize: minimumFileSize)
let scanner = DiskScanner(options: options)
let cancellation = ScanCancellation()
signal(SIGINT) { _ in
    cancellation.cancel()
}

var lastUpdate = Date.distantPast
let started = Date()

do {
    let tree = try scanner.scan(path: target, cancellation: cancellation, progress: { progress in
        guard !quiet else { return }
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) > 0.5 else { return }
        lastUpdate = now
        let line = "\r  \(ByteFormat.string(progress.bytes)) · \(progress.entries) objects · \(progress.currentPath.prefix(70))"
        FileHandle.standardError.write(Data(line.utf8))
    })
    if !quiet { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }

    if json {
        let report = CLIReport.make(tree: tree, budgetBytes: budgetBytes, limit: limit)
        let data = try report.encoded()
        if let outputPath {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        if let budget = report.budget, !budget.withinBudget {
            FileHandle.standardError.write(Data(
                "budget exceeded by \(ByteFormat.string(budget.exceededBy))\n".utf8
            ))
            exit(3)
        }
        exit(0)
    }

    print("")
    print("Path:            \(tree.rootPath)")
    print("Total on disk:   \(ByteFormat.string(tree.totalSize)) (\(tree.totalSize) bytes)")
    print("Files:           \(ByteFormat.count(tree.totalFiles))")
    print("Folders:         \(ByteFormat.count(tree.directoryCount()))")
    print("Nodes kept:      \(ByteFormat.count(tree.count))")
    print("Duration:        \(ByteFormat.duration(tree.report.duration))")
    if tree.report.duration > 0 {
        let rate = Double(tree.report.entriesRead) / tree.report.duration
        print("Entries/sec:     \(ByteFormat.count(Int(rate)))")
    }
    print("Scanner:         \(tree.report.usedBulkScanner ? "getattrlistbulk" : "readdir")")
    print("Skipped:         \(tree.report.skippedItems) items, \(tree.report.skippedMounts) mounts")
    if tree.report.hardLinkBytes > 0 {
        print("Hard links:      \(ByteFormat.string(tree.report.hardLinkBytes)) counted once")
    }
    if let first = tree.report.sampleSkippedPaths.first {
        print("First skipped:   \(first)")
    }

    let children = tree.children(of: 0).sorted { tree.node($0).size > tree.node($1).size }
    print("")
    print("Top folders/files in root:")
    for index in children.prefix(limit) {
        let node = tree.node(index)
        print(String(format: "  %-12@ %@", ByteFormat.string(node.size) as NSString, tree.name(of: index) as NSString))
    }

    let items = tree.largestItems(limit: limit)
    print("")
    print("Largest items:")
    for index in items {
        print(String(format: "  %-12@ %@", ByteFormat.string(tree.node(index).size) as NSString, tree.path(of: index) as NSString))
    }

    if let budgetBytes {
        let budget = CLIBudget(limitBytes: budgetBytes, totalBytes: tree.totalSize)
        print("")
        print("Budget:          \(ByteFormat.string(budgetBytes)) · \(budget.withinBudget ? "within budget" : "exceeded by \(ByteFormat.string(budget.exceededBy))")")
        if !budget.withinBudget { exit(3) }
    }

    print("")
    print("Elapsed wall clock: \(ByteFormat.duration(Date().timeIntervalSince(started)))")
} catch {
    FileHandle.standardError.write(Data("\nError: \(error.localizedDescription)\n".utf8))
    exit(2)
}
