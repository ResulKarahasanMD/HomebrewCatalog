import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("TapHealthDeriver")
struct TapHealthDeriverTests {
    // Response shapes checked against api.github.com on 2026-09-30: a transferred repo
    // (mojombo/jekyll) answers 301, and after the redirect 200 with the new full_name;
    // a deleted one (Homebrew/homebrew-cask-versions) answers 404 "Not Found".
    static let responses: [(requested: String, status: Int, body: String, health: TapHealth)] = [
        ("bysiber/homebrew-cleardisk", 200,
         #"{"full_name":"bysiber/homebrew-cleardisk","archived":false}"#, .healthy),
        ("garfieldfluffjr/homebrew-macnewfile", 200,
         #"{"full_name":"GarfieldFluffJr/homebrew-macnewfile","archived":false}"#, .healthy),
        ("someone/homebrew-old", 200,
         #"{"full_name":"someone/homebrew-old","archived":true}"#, .archived),
        ("mojombo/jekyll", 200,
         #"{"full_name":"jekyll/jekyll","archived":false}"#, .moved(newName: "jekyll/jekyll")),
        ("someone/homebrew-old", 200,
         #"{"full_name":"elsewhere/homebrew-old","archived":true}"#, .archived),
        ("Homebrew/homebrew-cask-versions", 404,
         #"{"message":"Not Found","status":"404"}"#, .missing),
        ("someone/homebrew-tap", 403,
         #"{"message":"API rate limit exceeded for 203.0.113.7. (But here's the good news: Authenticated requests get a higher rate limit.)"}"#,
         .rateLimited),
        ("someone/homebrew-tap", 429, #"{"message":"Too Many Requests"}"#, .rateLimited),
        ("someone/homebrew-tap", 403, #"{"message":"Repository access blocked"}"#, .unknown),
        ("someone/homebrew-tap", 500, "", .unknown),
        ("someone/homebrew-tap", 200, "<html>captive portal</html>", .unknown),
    ]

    @Test("a GitHub repo response maps to a tap health", arguments: responses)
    func derive(requested: String, status: Int, body: String, health: TapHealth) {
        #expect(TapHealth.derive(requestedRepo: requested, statusCode: status, body: Data(body.utf8)) == health)
    }

    static let remotes: [(remote: String?, repo: String?)] = [
        ("https://github.com/1broseidon/homebrew-tap", "1broseidon/homebrew-tap"),
        ("https://github.com/GarfieldFluffJr/homebrew-macnewfile.git", "GarfieldFluffJr/homebrew-macnewfile"),
        ("https://www.github.com/owner/homebrew-x/", "owner/homebrew-x"),
        ("git@github.com:owner/homebrew-x.git", "owner/homebrew-x"),
        ("https://gitlab.com/owner/homebrew-x", nil),
        ("https://github.com/owner", nil),
        (nil, nil),
    ]

    @Test("a tap's remote names the GitHub repo to check, when it is on GitHub", arguments: remotes)
    func githubRepo(remote: String?, repo: String?) {
        #expect(TapHealth.githubRepo(fromRemote: remote) == repo)
    }

    // Header values from a live api.github.com response on 2026-09-30.
    @Test("the rate limit is read from GitHub's X-RateLimit headers")
    func rateLimitHeaders() throws {
        let url = try #require(URL(string: "https://api.github.com/repos/bysiber/homebrew-cleardisk"))
        let withHeaders = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/2",
            headerFields: ["x-ratelimit-remaining": "55", "x-ratelimit-reset": "1790801360"]))
        let without = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/2", headerFields: [:]))

        #expect(GitHubService.rateLimit(from: withHeaders)
            == GitHubRateLimit(remaining: 55, reset: Date(timeIntervalSince1970: 1_790_801_360)))
        #expect(GitHubService.rateLimit(from: without) == nil)
    }
}
