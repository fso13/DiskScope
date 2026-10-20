import Foundation
import DiskScopeKit

// Small headless companion used for benchmarking and smoke testing the engine.
// Usage: diskscope-cli [--limit N] [--min-size BYTES] [--quiet] <path>

var path: String?
var limit = 15
var minimumFileSize: Int64 = 64 * 1024
var quiet = false

var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let argument = iterator.next() {
    switch argument {
    case "--limit":
        if let value = iterator.next(), let parsed = Int(value) { limit = parsed }
    case "--min-size":
        if let value = iterator.next(), let parsed = Int64(value) { minimumFileSize = parsed }
    case "--quiet":
        quiet = true
    case "--help", "-h":
        print("usage: diskscope-cli [--limit N] [--min-size BYTES] [--quiet] <path>")
        exit(0)
    default:
        path = argument
    }
}

guard let target = path else {
    print("usage: diskscope-cli [--limit N] [--min-size BYTES] [--quiet] <path>")
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
        FileHandle.standardError.write(Data("\r  \(ByteFormat.string(progress.bytes)) · \(progress.entries) объектов · \(progress.currentPath.prefix(70))".utf8))
    })
    if !quiet { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }

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

    print("")
    print("Elapsed wall clock: \(ByteFormat.duration(Date().timeIntervalSince(started)))")
} catch {
    FileHandle.standardError.write(Data("\nError: \(error.localizedDescription)\n".utf8))
    exit(2)
}
