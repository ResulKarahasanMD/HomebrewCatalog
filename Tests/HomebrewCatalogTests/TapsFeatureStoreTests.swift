import Foundation
import Testing
@testable import HomebrewCatalog

actor MockRepoFetcher: GitHubRepoFetching {
    var responses: [String: GitHubRepoResponse] = [:]
    var failing: Set<String> = []
    var delay: Duration = .zero
    private(set) var requested: [String] = []
    private var active = 0
    private(set) var maxConcurrent = 0

    func configure(responses: [String: GitHubRepoResponse] = [:], failing: Set<String> = [], delay: Duration = .zero) {
        self.responses = responses
        self.failing = failing
        self.delay = delay
    }

    func fetchRepo(_ fullName: String) async throws -> GitHubRepoResponse {
        requested.append(fullName)
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        defer { active -= 1 }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if failing.contains(fullName) { throw URLError(.notConnectedToInternet) }
        return responses[fullName] ?? .repo(fullName)
    }
}

extension GitHubRepoResponse {
    static func repo(_ fullName: String, archived: Bool = false, rateLimit: GitHubRateLimit? = nil) -> Self {
        GitHubRepoResponse(
            statusCode: 200, body: Data(#"{"full_name":"\#(fullName)","archived":\#(archived)}"#.utf8),
            rateLimit: rateLimit)
    }

    static func rateLimited(reset: Date) -> Self {
        GitHubRepoResponse(
            statusCode: 403, body: Data(#"{"message":"API rate limit exceeded for 203.0.113.7."}"#.utf8),
            rateLimit: GitHubRateLimit(remaining: 0, reset: reset))
    }
}

@MainActor
final class InMemoryTapHealthSettings: TapHealthSettings {
    var rateLimit: GitHubRateLimit?
    var autoRefreshMinutes = 0
}

private let now = Date(timeIntervalSince1970: 1_790_800_000)

private func tap(_ name: String, remote: String?, official: Bool = false) -> BrewTapInfo {
    BrewTapInfo(name: name, remote: remote, isOfficial: official, formulaCount: 1, caskCount: 0, isInstalled: true)
}

/// Third-party GitHub taps "user0/tap" … whose repos are "user0/homebrew-tap" ….
private func githubTaps(_ count: Int) -> [BrewTapInfo] {
    (0..<count).map { tap("user\($0)/tap", remote: "https://github.com/user\($0)/homebrew-tap") }
}

@MainActor
private struct Harness {
    let service = MockBrewService()
    let fetcher = MockRepoFetcher()
    let settings = InMemoryTapHealthSettings()
    let store: TapsFeatureStore

    init() {
        store = TapsFeatureStore(service: service, fetcher: fetcher, settings: settings, now: { now })
    }

    func load(_ taps: [BrewTapInfo]) async {
        await service.configureTaps(taps)
        await store.load()
    }
}

@Suite("TapsFeatureStore health")
@MainActor
struct TapHealthCheckTests {
    @Test("only third-party taps hosted on GitHub are checked")
    func onlyGitHubThirdPartyTapsAreChecked() async {
        let h = Harness()
        await h.load([
            tap("homebrew/core", remote: nil, official: true),
            tap("bysiber/cleardisk", remote: "https://github.com/bysiber/homebrew-cleardisk"),
            tap("someone/tools", remote: "https://gitlab.com/someone/homebrew-tools"),
        ])

        await h.store.checkHealth()

        #expect(await h.fetcher.requested == ["bysiber/homebrew-cleardisk"])
        #expect(h.store.health["bysiber/cleardisk"] == .healthy)
        #expect(h.store.health["someone/tools"] == .unknown)
        #expect(h.store.health["homebrew/core"] == nil)
    }

    @Test("each tap gets the health its GitHub repo reports")
    func eachTapGetsItsHealth() async {
        let h = Harness()
        await h.load([
            tap("a/old", remote: "https://github.com/a/homebrew-old"),
            tap("b/renamed", remote: "https://github.com/b/homebrew-renamed"),
            tap("c/gone", remote: "https://github.com/c/homebrew-gone"),
            tap("d/offline", remote: "https://github.com/d/homebrew-offline"),
        ])
        await h.fetcher.configure(
            responses: [
                "a/homebrew-old": .repo("a/homebrew-old", archived: true),
                "b/homebrew-renamed": .repo("newowner/homebrew-renamed"),
                "c/homebrew-gone": GitHubRepoResponse(
                    statusCode: 404, body: Data(#"{"message":"Not Found"}"#.utf8), rateLimit: nil),
            ],
            failing: ["d/homebrew-offline"])

        await h.store.checkHealth()

        #expect(h.store.health == [
            "a/old": .archived,
            "b/renamed": .moved(newName: "newowner/homebrew-renamed"),
            "c/gone": .missing,
            "d/offline": .unknown,
        ])
    }

    @Test("at most five checks run at once")
    func checksAreThrottled() async {
        let h = Harness()
        await h.load(githubTaps(12))
        await h.fetcher.configure(delay: .milliseconds(30))

        await h.store.checkHealth()

        #expect(await h.fetcher.requested.count == 12)
        #expect(await h.fetcher.maxConcurrent == 5)
    }

    @Test("a rate-limited response stops the checks not yet started")
    func rateLimitStopsTheGroup() async {
        let h = Harness()
        let reset = now.addingTimeInterval(900)
        await h.load(githubTaps(12))
        let limited = Dictionary(uniqueKeysWithValues: (0..<12).map {
            ("user\($0)/homebrew-tap", GitHubRepoResponse.rateLimited(reset: reset))
        })
        await h.fetcher.configure(responses: limited)

        await h.store.checkHealth()

        #expect(await h.fetcher.requested.count == 5)
        #expect(Set(h.store.health.values) == [.rateLimited])
        #expect(h.store.health.count == 12)
        #expect(h.store.healthPausedUntil == reset)
        #expect(h.settings.rateLimit == GitHubRateLimit(remaining: 0, reset: reset))
    }

    @Test("health is checked once per session unless refreshed by hand")
    func healthIsCachedForTheSession() async {
        let h = Harness()
        await h.load(githubTaps(3))

        await h.store.checkHealthIfNeeded()
        await h.store.checkHealthIfNeeded()
        #expect(await h.fetcher.requested.count == 3)

        await h.load(githubTaps(4))
        await h.store.checkHealthIfNeeded()
        #expect(await h.fetcher.requested.count == 4)
        #expect(await h.fetcher.requested.last == "user3/homebrew-tap")

        await h.store.checkHealth()
        #expect(await h.fetcher.requested.count == 8)
    }
}

@Suite("RateLimitGate")
@MainActor
struct RateLimitGateTests {
    @Test("checks are skipped when the stored rate limit cannot cover them plus two",
          arguments: [(3, false), (11, false), (12, true)])
    func storedLimitGatesChecks(remaining: Int, runs: Bool) async {
        let h = Harness()
        let reset = now.addingTimeInterval(600)
        h.settings.rateLimit = GitHubRateLimit(remaining: remaining, reset: reset)
        await h.load(githubTaps(10))

        await h.store.checkHealth()

        #expect(await h.fetcher.requested.count == (runs ? 10 : 0))
        #expect(Set(h.store.health.values) == (runs ? [.healthy] : [.rateLimited]))
        #expect(h.store.healthPausedUntil == (runs ? nil : reset))
    }

    @Test("an expired rate-limit window does not block checks")
    func expiredWindowDoesNotBlock() async {
        let h = Harness()
        h.settings.rateLimit = GitHubRateLimit(remaining: 0, reset: now.addingTimeInterval(-1))
        await h.load(githubTaps(10))

        await h.store.checkHealth()

        #expect(await h.fetcher.requested.count == 10)
    }

    @Test("a paused check keeps the results it already had")
    func pausedCheckKeepsEarlierResults() async {
        let h = Harness()
        await h.load(githubTaps(2))
        await h.store.checkHealth()
        h.settings.rateLimit = GitHubRateLimit(remaining: 0, reset: now.addingTimeInterval(600))
        await h.load(githubTaps(3))

        await h.store.checkHealth()

        #expect(h.store.health == ["user0/tap": .healthy, "user1/tap": .healthy, "user2/tap": .rateLimited])
    }

    @Test("responses update the stored rate limit to the lowest remaining count")
    func headersUpdateStoredLimit() async {
        let h = Harness()
        let reset = now.addingTimeInterval(1_800)
        await h.load(githubTaps(3))
        await h.fetcher.configure(responses: [
            "user0/homebrew-tap": .repo("user0/homebrew-tap", rateLimit: GitHubRateLimit(remaining: 40, reset: reset)),
            "user1/homebrew-tap": .repo("user1/homebrew-tap", rateLimit: GitHubRateLimit(remaining: 38, reset: reset)),
            "user2/homebrew-tap": .repo("user2/homebrew-tap", rateLimit: GitHubRateLimit(remaining: 39, reset: reset)),
        ])

        await h.store.checkHealth()

        #expect(h.settings.rateLimit == GitHubRateLimit(remaining: 38, reset: reset))
    }

    @Test("automatic refreshes skip health checks when the interval is under an hour",
          arguments: [
              (15, TapsFeatureStore.RefreshSource.automatic, false),
              (120, .automatic, true),
              (15, .manual, true),
          ])
    func automaticRefreshGate(minutes: Int, source: TapsFeatureStore.RefreshSource, runs: Bool) async {
        let h = Harness()
        h.settings.autoRefreshMinutes = minutes
        await h.load(githubTaps(2))

        await h.store.checkHealth(source: source)

        #expect(await h.fetcher.requested.count == (runs ? 2 : 0))
    }
}
