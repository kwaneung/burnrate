import Foundation

enum AntigravitySessionReader {
    static var oauthTokenPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/antigravity-oauth-token")
            .path
    }

    static var hasActiveSession: Bool {
        loadStoredToken()?.refreshToken.isEmpty == false
    }

    struct StoredToken {
        let accessToken: String
        let refreshToken: String
        let expiry: Date?
    }

    private struct OAuthCredentials {
        let clientID: String
        let clientSecret: String
    }

    static func loadStoredToken() -> StoredToken? {
        guard FileManager.default.fileExists(atPath: oauthTokenPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: oauthTokenPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokenObject = json["token"] as? [String: Any],
              let refreshToken = tokenObject["refresh_token"] as? String,
              !refreshToken.isEmpty else {
            return nil
        }

        let accessToken = tokenObject["access_token"] as? String ?? ""
        let expiry = parseExpiry(tokenObject["expiry"] as? String)
        return StoredToken(accessToken: accessToken, refreshToken: refreshToken, expiry: expiry)
    }

    static func resolveAccessToken(completion: @escaping (String?) -> Void) {
        guard let stored = loadStoredToken() else {
            completion(nil)
            return
        }

        if let expiry = stored.expiry, expiry > Date().addingTimeInterval(60), !stored.accessToken.isEmpty {
            completion(stored.accessToken)
            return
        }

        refreshAccessToken(refreshToken: stored.refreshToken, completion: completion)
    }

    private static func refreshAccessToken(refreshToken: String, completion: @escaping (String?) -> Void) {
        guard let credentials = resolveCliOAuthCredentials() else {
            completion(nil)
            return
        }

        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  !accessToken.isEmpty else {
                completion(nil)
                return
            }
            completion(accessToken)
        }.resume()
    }

    private static func resolveCliOAuthCredentials() -> OAuthCredentials? {
        let environment = ProcessInfo.processInfo.environment
        if let clientID = environment["ANTIGRAVITY_CLIENT_ID"],
           let clientSecret = environment["ANTIGRAVITY_CLIENT_SECRET"],
           !clientID.isEmpty,
           !clientSecret.isEmpty {
            return OAuthCredentials(clientID: clientID, clientSecret: clientSecret)
        }

        for path in candidateAgyPaths() {
            if let credentials = extractCredentials(fromAgyBinaryAt: path) {
                return credentials
            }
        }

        return nil
    }

    private static func candidateAgyPaths() -> [String] {
        var paths: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        if let whichPath = shellExecutablePath("agy") {
            paths.append(whichPath)
        }

        paths.append(contentsOf: [
            "\(home)/.local/bin/agy",
            "\(home)/.gemini/antigravity-cli/bin/agy",
            "/usr/local/bin/agy",
            "/opt/homebrew/bin/agy"
        ])

        var seen = Set<String>()
        return paths.filter { path in
            guard !path.isEmpty, seen.insert(path).inserted else { return false }
            return FileManager.default.isExecutableFile(atPath: path)
        }
    }

    private static func shellExecutablePath(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else {
            return nil
        }
        return path
    }

    private static func extractCredentials(fromAgyBinaryAt path: String) -> OAuthCredentials? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let clientIDPattern = #"\d{10,}-[a-z0-9]+\.apps\.googleusercontent\.com"#
        let secretPattern = #"GOCSPX-[A-Za-z0-9_-]+"#

        var searchRange = content.startIndex..<content.endIndex
        while let clientIDRange = content.range(of: clientIDPattern, options: .regularExpression, range: searchRange) {
            let clientID = String(content[clientIDRange])
            let searchStart = clientIDRange.upperBound
            let searchEnd = content.index(searchStart, offsetBy: 512, limitedBy: content.endIndex) ?? content.endIndex
            let secretWindow = String(content[searchStart..<searchEnd])

            if let secretRange = secretWindow.range(of: secretPattern, options: .regularExpression) {
                return OAuthCredentials(
                    clientID: clientID,
                    clientSecret: String(secretWindow[secretRange])
                )
            }

            searchRange = clientIDRange.upperBound..<content.endIndex
        }

        return nil
    }

    private static func parseExpiry(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
