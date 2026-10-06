import XCTest
@testable import FileLockPeekKit
@testable import MacPeekCore

final class FileHolderParserTests: XCTestCase {
    func testSingleHolderWithEscapedCommandName() throws {
        let holders = FileHolderParser.parse(try fixture("file_single"))
        XCTAssertEqual(holders.count, 1)
        let h = try XCTUnwrap(holders.first)
        XCTAssertEqual(h.pid, 18432)
        XCTAssertEqual(h.processName, "Docker Desktop")
        XCTAssertEqual(h.user, "mohit")
        XCTAssertEqual(h.files, [OpenFile(path: "/Users/mohit/data.db", descriptor: "23u", kind: .open(.readWrite), lock: nil, fileType: "REG")])
        XCTAssertEqual(h.primaryKind, .open(.readWrite))
    }

    func testMultipleHoldersGroupedAndSortedWithLocksFirstAsOpens() throws {
        let holders = FileHolderParser.parse(try fixture("file_multi_holders"))
        XCTAssertEqual(Set(holders.map(\.pid)), [18432, 20311, 700])
        XCTAssertEqual(holders.count, 3)
        XCTAssertEqual(holders.first { $0.pid == 18432 }?.hasLock, true)
        XCTAssertEqual(holders.first { $0.pid == 20311 }?.hasLock, false)
        XCTAssertEqual(holders.first { $0.pid == 20311 }?.primaryKind, .open(.read))
        // Sorted: same kind -> by process name (case-insensitive): Docker, mds, sqlite3.
        XCTAssertEqual(holders.map(\.processName), ["Docker", "mds", "sqlite3"])
        XCTAssertEqual(holders.first { $0.pid == 700 }?.user, "root")
    }

    func testFolderScanGroupsFilesPerProcessAndClassifiesCwd() throws {
        let holders = FileHolderParser.parse(try fixture("dir_scan"))
        XCTAssertEqual(holders.count, 3)
        let bash = try XCTUnwrap(holders.first { $0.processName == "bash" })
        XCTAssertEqual(bash.files.map(\.kind), [.workingDirectory], "the root directory (rtd) is never interesting")
        let vim = try XCTUnwrap(holders.first { $0.processName == "vim" })
        XCTAssertEqual(vim.files.count, 2)
        XCTAssertEqual(vim.primaryKind, .open(.readWrite))
        let node = try XCTUnwrap(holders.first { $0.processName == "node" })
        XCTAssertEqual(node.files.map(\.kind), [.open(.write), .workingDirectory])
        // Real opens sort before processes that merely have the folder as their working directory.
        XCTAssertEqual(holders.map(\.processName), ["node", "vim", "bash"])
    }

    func testKindsExecutableMemoryMappedAndUnknownDescriptors() throws {
        let h = try XCTUnwrap(FileHolderParser.parse(try fixture("kinds")).first)
        let kinds = Dictionary(uniqueKeysWithValues: h.files.map { ($0.descriptor, $0.kind) })
        XCTAssertEqual(kinds["txt"], .executable)
        XCTAssertEqual(kinds["mem"], .memoryMapped)
        XCTAssertEqual(kinds["3r"], .open(.read))
        XCTAssertEqual(kinds["NOFD"], .other("NOFD"))
        XCTAssertEqual(h.primaryKind, .open(.read))
    }

    func testLockCharactersAreDescribed() throws {
        let h = try XCTUnwrap(FileHolderParser.parse(try fixture("locks")).first)
        let locks = Dictionary(uniqueKeysWithValues: h.files.map { ($0.descriptor, $0.lock) })
        XCTAssertEqual(locks["5uW"], "write lock (whole file)")
        XCTAssertEqual(locks["6wr"], "read lock (part of file)")
        XCTAssertEqual(locks["7rR"], "read lock (whole file)")
        XCTAssertEqual(locks["9ux"], "exclusive lock")
        XCTAssertTrue(h.hasLock)
    }

    func testEscapedPathsAndNames() throws {
        let h = try XCTUnwrap(FileHolderParser.parse(try fixture("escaped_names")).first)
        XCTAssertEqual(h.processName, "My App")
        XCTAssertEqual(h.files.first?.path, "/Users/mohit/My Documents/Notes v2.txt")
    }

    func testOwnProcessIsExcluded() throws {
        let holders = FileHolderParser.parse(try fixture("includes_self"), excludingPID: 4242)
        XCTAssertEqual(holders.map(\.pid), [18432])
        XCTAssertEqual(FileHolderParser.parse(try fixture("includes_self")).count, 2)
    }

    func testMalformedOutputDoesNotCrashAndKeepsOnlyValidRecords() throws {
        let holders = FileHolderParser.parse(try fixture("malformed"))
        XCTAssertEqual(holders.map(\.pid), [56])
        XCTAssertEqual(holders.first?.files.first?.path, "/valid/file")
    }

    func testEmptyOutput() throws {
        XCTAssertEqual(FileHolderParser.parse(try fixture("empty")), [])
        XCTAssertEqual(FileHolderParser.parse("\n\n"), [])
    }

    func testDuplicateFilesAreMerged() {
        let text = "p1\ncx\nf3r\ntREG\nn/a\nf3r\ntREG\nn/a\n"
        XCTAssertEqual(FileHolderParser.parse(text).first?.files.count, 1)
    }
}
