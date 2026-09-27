import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper around the system libsqlite3. No third-party dependencies.
final class Database {
    private var handle: OpaquePointer?
    let path: String

    init(path: String) {
        self.path = path
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            fatalError("Unable to open database at \(path): \(msg)")
        }
        sqlite3_busy_timeout(handle, 3000)
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA foreign_keys = ON;")
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    @discardableResult
    func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            if let err {
                NSLog("HumanRAM SQL error: \(String(cString: err)) for: \(sql)")
                sqlite3_free(err)
            }
            return false
        }
        return true
    }

    func run(_ sql: String, _ binds: [Any?] = []) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("HumanRAM prepare failed: \(lastError) for: \(sql)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, binds)
        if sqlite3_step(stmt) != SQLITE_DONE {
            NSLog("HumanRAM step failed: \(lastError) for: \(sql)")
        }
    }

    func query(_ sql: String, _ binds: [Any?] = [], _ row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("HumanRAM prepare failed: \(lastError) for: \(sql)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, binds)
        while sqlite3_step(stmt) == SQLITE_ROW {
            row(stmt!)
        }
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(handle))
    }

    private func bind(_ stmt: OpaquePointer?, _ binds: [Any?]) {
        for (i, value) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case nil:
                sqlite3_bind_null(stmt, idx)
            case let v as String:
                sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Bool:
                sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            case let v as Double:
                sqlite3_bind_double(stmt, idx, v)
            case let v as Date:
                sqlite3_bind_double(stmt, idx, v.timeIntervalSince1970)
            default:
                sqlite3_bind_text(stmt, idx, String(describing: value!), -1, SQLITE_TRANSIENT)
            }
        }
    }
}

// MARK: - Column helpers

extension OpaquePointer {
    func string(_ i: Int32) -> String? {
        guard let c = sqlite3_column_text(self, i) else { return nil }
        return String(cString: c)
    }

    func double(_ i: Int32) -> Double? {
        guard sqlite3_column_type(self, i) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(self, i)
    }

    func int(_ i: Int32) -> Int {
        Int(sqlite3_column_int64(self, i))
    }

    func bool(_ i: Int32) -> Bool {
        sqlite3_column_int64(self, i) != 0
    }

    func date(_ i: Int32) -> Date? {
        guard let d = double(i) else { return nil }
        return Date(timeIntervalSince1970: d)
    }
}