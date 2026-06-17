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
        guard extractSubFromJWT(token) != nil else {
            return false
        }
        return !isAccessTokenExpired(token)
    }

    static var hasStoredSession: Bool {
        guard let token = readAccessToken(), !token.isEmpty else {
            return false
        }
        return extractSubFromJWT(token) != nil
    }

    static func readAccessToken() -> String? {
        readStateValue(forKey: "cursorAuth/accessToken")
    }

    static func isAccessTokenExpired(_ jwt: String, bufferSeconds: TimeInterval = 60) -> Bool {
        guard let expiry = extractExpiryFromJWT(jwt) else {
            return false
        }
        return expiry <= Date().addingTimeInterval(bufferSeconds)
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
        decodeJWTPayload(jwt)?["sub"] as? String
    }

    static func extractExpiryFromJWT(_ jwt: String) -> Date? {
        guard let payload = decodeJWTPayload(jwt) else {
            return nil
        }

        if let exp = payload["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = payload["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }

    private static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
