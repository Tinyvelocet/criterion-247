import Foundation

/// Reads the TMDb API key from the environment or a local config file.
/// NEVER committed to git — see `App/.gitignore` and the README setup note.
enum AppConfig {
    static let appGroupID = "group.dev.criterion247"
    /// Where the user drops their key: ~/.criterion247/tmdb.key (plain text).
    static let keyFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".criterion247").appendingPathComponent("tmdb.key")

    static var tmdbAPIKey: String? {
        // 1. Environment override.
        if let env = ProcessInfo.processInfo.environment["TMDB_API_KEY"], !env.isEmpty {
            return env
        }
        // 2. Local key file.
        if let data = try? Data(contentsOf: keyFileURL),
           let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            return s
        }
        return nil
    }
}