import Foundation
import Observation

/// GitHub's unauthenticated rate limit, from the `X-RateLimit-*` headers of a response.
struct GitHubRateLimit: Equatable, Sendable {
    let remaining: Int
    let reset: Date
}

struct GitHubRepoResponse: Sendable {
    let statusCode: Int
    let body: Data
    let rateLimit: GitHubRateLimit?
}

/// `GET https://api.github.com/repos/{owner}/{repo}`, following redirects.
protocol GitHubRepoFetching: Sendable {
    func fetchRepo(_ fullName: String) async throws -> GitHubRepoResponse
}

@MainActor
protocol TapHealthSettings: AnyObject {
    /// The last rate limit GitHub reported, kept between launches.
    var rateLimit: GitHubRateLimit? { get set }
    /// Minutes between automatic refreshes; 0 when they are off.
    var autoRefreshMinutes: Int { get }
}

/// Installed taps, and the GitHub health of the third-party ones: archived, moved or
/// missing repositories. Health is checked once per session unless refreshed by hand.
@Observable
@MainActor
final class TapsFeatureStore {
    enum RefreshSource: Sendable {
        case manual, automatic
    }

    private(set) var taps: [BrewTapInfo] = []
    private(set) var isLoading = false
    private(set) var error: String?
    /// Health by tap name. Official taps have no entry.
    private(set) var health: [String: TapHealth] = [:]
    private(set) var isCheckingHealth = false
    /// Set while checks are skipped for GitHub's rate limit: the time it resets.
    private(set) var healthPausedUntil: Date?

    /// Unauthenticated GitHub allows 60 requests an hour; five at a time is plenty.
    static let maxConcurrentChecks = 5

    private let service: any BrewService
    private let fetcher: any GitHubRepoFetching
    private let settings: any TapHealthSettings
    private let now: @MainActor () -> Date
    private let redactor = OutputRedactor()
    private var hasLoaded = false
    private var loadGeneration = 0

    init(
        service: any BrewService,
        fetcher: any GitHubRepoFetching,
        settings: any TapHealthSettings,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.service = service
        self.fetcher = fetcher
        self.settings = settings
        self.now = now
    }

    // MARK: - Taps

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        do {
            let loaded = try await service.listTaps()
            guard generation == loadGeneration else { return }
            taps = loaded
            hasLoaded = true
        } catch {
            guard generation == loadGeneration, !(error is CancellationError) else { return }
            taps = []
            self.error = error.localizedDescription
        }
    }

    /// Runs `brew tap <name>`; returns nil when brew could not be run.
    func add(_ name: String, onOutput: @escaping @MainActor (String) -> Void) async -> ProcessResult? {
        do {
            let result = try await OrderedOutput.run(sink: onOutput) {
                try await service.addTap(name: name, onOutput: $0)
            }
            await load()
            await checkHealthIfNeeded()
            return result
        } catch {
            return nil
        }
    }

    func remove(_ name: String) async -> Bool {
        do {
            let result = try await service.removeTap(name: name)
            await load()
            if result.exitCode == 0 {
                health[name] = nil
            }
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    // MARK: - Health

    /// Checks the third-party taps that have no result yet.
    func checkHealthIfNeeded() async {
        await check(githubCandidates().filter { health[$0.tap] == nil })
    }

    /// Re-checks every third-party tap. Automatic refreshes under an hour apart skip it,
    /// so the checks stay well inside GitHub's hourly limit.
    func checkHealth(source: RefreshSource = .manual) async {
        if source == .automatic, settings.autoRefreshMinutes < 60 { return }
        await check(githubCandidates())
    }

    private struct Candidate: Sendable {
        let tap: String
        let repo: String
    }

    /// Third-party taps on GitHub. Those hosted elsewhere cannot be checked and get `.unknown`.
    private func githubCandidates() -> [Candidate] {
        var candidates: [Candidate] = []
        for tap in taps where !tap.isOfficial {
            if let repo = TapHealth.githubRepo(fromRemote: tap.remote) {
                candidates.append(Candidate(tap: tap.name, repo: repo))
            } else {
                health[tap.name] = .unknown
            }
        }
        return candidates
    }

    private func check(_ candidates: [Candidate]) async {
        guard !candidates.isEmpty else { return }
        // Two spare requests: a moved repo costs two, the redirect and the new location.
        if let limit = settings.rateLimit, limit.reset > now(), limit.remaining < candidates.count + 2 {
            pause(candidates, until: limit.reset)
            return
        }
        healthPausedUntil = nil
        isCheckingHealth = true
        defer { isCheckingHealth = false }

        let fetcher = fetcher
        var pending = candidates[...]
        await withTaskGroup(of: (Candidate, GitHubRepoResponse?).self) { group in
            for _ in 0..<Self.maxConcurrentChecks {
                guard let next = pending.popFirst() else { break }
                group.addTask { (next, try? await fetcher.fetchRepo(next.repo)) }
            }
            while let (candidate, response) = await group.next() {
                if let response {
                    record(response.rateLimit)
                    let result = TapHealth.derive(
                        requestedRepo: candidate.repo, statusCode: response.statusCode, body: response.body)
                    store(result, for: candidate.tap)
                    if result == .rateLimited {
                        // Anything not started yet would be refused as well.
                        pause(Array(pending), until: response.rateLimit?.reset)
                        pending.removeAll()
                    }
                } else {
                    // The request itself failed (offline, DNS): nothing is known.
                    store(.unknown, for: candidate.tap)
                }
                if let next = pending.popFirst() {
                    group.addTask { (next, try? await fetcher.fetchRepo(next.repo)) }
                }
            }
        }
    }

    /// A rate-limited answer never replaces a real result from earlier.
    private func store(_ result: TapHealth, for tap: String) {
        if result == .rateLimited, let existing = health[tap], existing != .rateLimited { return }
        health[tap] = result
    }

    private func pause(_ candidates: [Candidate], until reset: Date?) {
        for candidate in candidates {
            store(.rateLimited, for: candidate.tap)
        }
        healthPausedUntil = reset
    }

    /// Responses arrive out of order, so within one window keep the lowest count.
    private func record(_ limit: GitHubRateLimit?) {
        guard let limit else { return }
        if let current = settings.rateLimit, current.reset == limit.reset, current.remaining <= limit.remaining {
            return
        }
        settings.rateLimit = limit
    }
}
