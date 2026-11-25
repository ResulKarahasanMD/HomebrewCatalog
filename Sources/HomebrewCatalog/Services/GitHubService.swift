import CryptoKit
import Foundation

actor GitHubService {
    static let shared = GitHubService()
    
    private let session: URLSession
    private let cache = CatalogCache.shared
    
    private init() {
        let config = NetworkSessionConfiguration.apiClient(requestTimeout: 30)
        self.session = URLSession(configuration: config)
    }
    
    /// Fetches the raw README.md content for a given Homebrew item
    func fetchREADME(for item: any BrewItem) async throws -> String {
        // Try to extract GitHub repo from homepage
        guard let homepage = item.homepage,
              let repoInfo = Self.extractGitHubRepo(from: homepage) else {
            throw GitHubError.noGitHubRepo
        }
        
        let cacheKey = Self.readmeCacheKey(for: item.id)
        
        // Check cache first
        if let cached = try? await loadCachedREADME(key: cacheKey) {
            return cached
        }
        
        // Try main branch first, then master
        let branches = ["main", "master"]
        for branch in branches {
            guard let url = URL(string: "https://raw.githubusercontent.com/\(repoInfo.owner)/\(repoInfo.repo)/\(branch)/README.md") else {
                continue
            }

            do {
                let (data, response) = try await session.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }
                
                if let markdown = String(data: data, encoding: .utf8) {
                    try? await cacheREADME(markdown, key: cacheKey)
                    return markdown
                }
            } catch {
                continue
            }
        }
        
        throw GitHubError.readmeNotFound
    }
    
    // MARK: - Private Helpers
    
    /// File-name-safe cache key. The id comes from catalog JSON and must not shape the
    /// path, so it is hashed: "../../x" can no longer leave the `Readmes` directory.
    static func readmeCacheKey(for id: String) -> String {
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return "readme_\(digest)"
    }

    static func readmeCacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HomebrewCatalog/Readmes", isDirectory: true)
    }

    static func readmeCacheFile(key: String, in directory: URL = readmeCacheDirectory()) -> URL {
        directory.appendingPathComponent("\(key).md")
    }

    static func extractGitHubRepo(from urlString: String) -> (owner: String, repo: String)? {
        guard let url = URL(string: urlString) else { return nil }
        
        let host = url.host?.lowercased() ?? ""
        guard host == "github.com" || host == "www.github.com" else { return nil }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }

        // Both parts are interpolated into a request URL: keep them to GitHub's own alphabet.
        let owner = pathComponents[0]
        let repo = pathComponents[1]
        let namePattern = #"\A[A-Za-z0-9._-]{1,100}\z"#
        guard owner.range(of: namePattern, options: .regularExpression) != nil,
            repo.range(of: namePattern, options: .regularExpression) != nil,
            owner != "..", repo != "..", owner != ".", repo != "."
        else { return nil }

        return (owner: owner, repo: repo)
    }
    
    private func cacheREADME(_ content: String, key: String) async throws {
        let cacheDir = Self.readmeCacheDirectory()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let fileURL = Self.readmeCacheFile(key: key, in: cacheDir)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func loadCachedREADME(key: String) async throws -> String? {
        let fileURL = Self.readmeCacheFile(key: key)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

enum GitHubError: Error, LocalizedError {
    case noGitHubRepo
    case readmeNotFound
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noGitHubRepo:
            return "No GitHub repository found for this item"
        case .readmeNotFound:
            return "README.md not found in repository"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
extension GitHubService: GitHubRepoFetching {
    /// Unauthenticated `GET /repos/{owner}/{repo}`. URLSession follows the 301 GitHub sends
    /// for a renamed or transferred repo, so the body then names the new location.
    func fetchRepo(_ fullName: String) async throws -> GitHubRepoResponse {
        guard let url = URL(string: "https://api.github.com/repos/\(fullName)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // The rate-limit headers must describe now, not a cached answer.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return GitHubRepoResponse(statusCode: http.statusCode, body: data, rateLimit: Self.rateLimit(from: http))
    }

    static func rateLimit(from response: HTTPURLResponse) -> GitHubRateLimit? {
        guard let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init),
            let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init)
        else { return nil }
        return GitHubRateLimit(remaining: remaining, reset: Date(timeIntervalSince1970: reset))
    }
}

/// Keeps GitHub's last reported rate limit in UserDefaults, so a relaunch within the same
/// hour does not spend requests GitHub will refuse.
@MainActor
final class UserDefaultsTapHealthSettings: TapHealthSettings {
    private static let remainingKey = "github.rateLimit.remaining"
    private static let resetKey = "github.rateLimit.reset"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var rateLimit: GitHubRateLimit? {
        get {
            guard let remaining = defaults.object(forKey: Self.remainingKey) as? Int,
                let reset = defaults.object(forKey: Self.resetKey) as? Double
            else { return nil }
            return GitHubRateLimit(remaining: remaining, reset: Date(timeIntervalSince1970: reset))
        }
        set {
            if let newValue {
                defaults.set(newValue.remaining, forKey: Self.remainingKey)
                defaults.set(newValue.reset.timeIntervalSince1970, forKey: Self.resetKey)
            } else {
                defaults.removeObject(forKey: Self.remainingKey)
                defaults.removeObject(forKey: Self.resetKey)
            }
        }
    }

    var autoRefreshMinutes: Int {
        defaults.integer(forKey: "autoRefreshInterval")
    }
}
