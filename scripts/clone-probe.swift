#!/usr/bin/env swift
import Darwin
import Foundation

/// Prints public APFS clone attributes for a source file and a clone created
/// with clonefile(2). Run: swift scripts/clone-probe.swift
struct CloneInfo {
    var cloneID: UInt64?
    var refCount: UInt32?
    var privateSize: Int64?
    var flags: UInt64?
}

func probe(_ path: String) -> CloneInfo {
    var attrs = attrlist()
    attrs.bitmapcount = 5
    attrs.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS)
    attrs.forkattr = UInt32(ATTR_CMNEXT_CLONEID)
        | UInt32(ATTR_CMNEXT_CLONE_REFCNT)
        | UInt32(ATTR_CMNEXT_PRIVATESIZE)
        | UInt32(ATTR_CMNEXT_EXT_FLAGS)
    var buffer = [UInt8](repeating: 0, count: 4096)
    let result = getattrlist(
        path, &attrs, &buffer, buffer.count,
        UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_PACK_INVAL_ATTRS)
    )
    guard result == 0 else { return CloneInfo() }
    let returnedFork = buffer.withUnsafeBytes {
        $0.loadUnaligned(fromByteOffset: 20, as: UInt32.self)
    }
    var info = CloneInfo()
    var cursor = 24
    if returnedFork & UInt32(ATTR_CMNEXT_PRIVATESIZE) != 0 {
        info.privateSize = buffer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
        }
        cursor += 8
    }
    if returnedFork & UInt32(ATTR_CMNEXT_CLONEID) != 0 {
        info.cloneID = buffer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: cursor, as: UInt64.self)
        }
        cursor += 8
    }
    if returnedFork & UInt32(ATTR_CMNEXT_EXT_FLAGS) != 0 {
        info.flags = buffer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: cursor, as: UInt64.self)
        }
        cursor += 8
    }
    if returnedFork & UInt32(ATTR_CMNEXT_CLONE_REFCNT) != 0 {
        info.refCount = buffer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: cursor, as: UInt32.self)
        }
    }
    return info
}

func describe(_ label: String, _ info: CloneInfo) {
    print(
        label,
        "cloneID=\(info.cloneID.map(String.init) ?? "—")",
        "refcnt=\(info.refCount.map(String.init) ?? "—")",
        "private=\(info.privateSize.map(String.init) ?? "—")",
        "flags=\(info.flags.map { String(format: "0x%llx", $0) } ?? "—")"
    )
}

let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("DiskScopeCloneProbe-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

let source = directory.appendingPathComponent("source.bin")
let clone = directory.appendingPathComponent("clone.bin")
try Data(repeating: 0x41, count: 10_000_000).write(to: source)
guard clonefile(source.path, clone.path, 0) == 0 else {
    print("clonefile failed: \(String(cString: strerror(errno)))")
    exit(1)
}

describe("source  ", probe(source.path))
describe("clone   ", probe(clone.path))

let handle = try FileHandle(forWritingTo: clone)
try handle.seekToEnd()
try handle.write(contentsOf: Data(repeating: 0x42, count: 1_000_000))
try handle.close()
describe("source+ ", probe(source.path))
describe("clone+  ", probe(clone.path))
