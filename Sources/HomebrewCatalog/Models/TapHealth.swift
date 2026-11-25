import Foundation

/// A third-party tap's repository state on GitHub.
enum TapHealth: Hashable, Sendable {
    case healthy
    case archived
    /// Renamed or transferred; GitHub redirects to the repository under this name.
    case moved(newName: String)
    /// Deleted or made private.
    case missing
    /// Not checked because GitHub's unauthenticated rate limit ran out.
    case rateLimited
    case unknown

    /// True for the states that suggest removing the tap.
    var isProblem: Bool {
        switch self {
        case .archived, .moved, .missing: true
        case .healthy, .rateLimited, .unknown: false
        }
    }

    /// Maps the response of `GET /repos/{owner}/{repo}`, after redirects, to a health.
    /// GitHub answers a renamed or transferred repo with 301, so a followed redirect shows
    /// up as a `full_name` that differs from the one requested.
    static func derive(requestedRepo: String, statusCode: Int, body: Data) -> TapHealth {
        struct Repo: Decodable {
            let full_name: String
            let archived: Bool
        }
        struct Message: Decodable {
            let message: String
        }

        switch statusCode {
        case 200:
            guard let repo = try? JSONDecoder().decode(Repo.self, from: body) else { return .unknown }
            if repo.archived { return .archived }
            if repo.full_name.caseInsensitiveCompare(requestedRepo) != .orderedSame {
                return .moved(newName: repo.full_name)
            }
            return .healthy
        case 404:
            return .missing
        case 429:
            return .rateLimited
        case 403:
            let message = (try? JSONDecoder().decode(Message.self, from: body))?.message ?? ""
            return message.localizedCaseInsensitiveContains("rate limit") ? .rateLimited : .unknown
        default:
            return .unknown
        }
    }

    /// "owner/repo" for a tap whose remote is on GitHub (https or ssh), else nil.
    static func githubRepo(fromRemote remote: String?) -> String? {
        guard let remote else { return nil }
        let path: Substring
        if let ssh = remote.range(of: "git@github.com:") {
            path = remote[ssh.upperBound...]
        } else if let url = URL(string: remote), let host = url.host?.lowercased(),
            host == "github.com" || host == "www.github.com"
        {
            path = Substring(url.path)
        } else {
            return nil
        }

        let parts = path.split(separator: "/")
        guard parts.count == 2 else { return nil }
        var repo = String(parts[1])
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        return "\(parts[0])/\(repo)"
    }
}
