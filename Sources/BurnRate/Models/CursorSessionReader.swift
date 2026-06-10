import Foundation
import SQLite3

enum CursorSessionReader {
    static var stateDatabasePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
    }

    static var hasActiveSession: Bool {
        guard let token = readAccessToken(), !token.isEmpty else {
            return false
        }
        return extractSubFromJWT(token) != nil
    }

    static func readAccessToken() -> String? {
        readStateValue(forKey: "cursorAuth/accessToken")
    }

    private static func readStateValue(forKey key: String) -> String? {
        guard FileManager.default.fileExists(atPath: stateDatabasePath) else {
            return nil
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(stateDatabasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let query = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let valuePointer = sqlite3_column_text(statement, 0) else {
            return nil
        }

        return String(cString: valuePointer)
    }

    static func extractSubFromJWT(_ jwt: String) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        var base64 = parts[1]

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        base64 = base64.replacingOccurrences(of: "-", with: "+")
        base64 = base64.replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        return sub
    }
}
