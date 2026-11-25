import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("README cache key")
struct ReadmeCacheKeyTests {
    @Test("readmeCacheKeyIsFlat: the key is readme_ + SHA-256 hex whatever the id", arguments: [
        "wget", "../../x", "a/b/c", "/etc/passwd", "..", "name with spaces", "",
    ])
    func keyIsFlat(_ id: String) {
        let key = GitHubService.readmeCacheKey(for: id)
        #expect(key.range(of: #"\Areadme_[0-9a-f]{64}\z"#, options: .regularExpression) != nil)

        let directory = URL(fileURLWithPath: "/tmp/hb-readmes-\(UUID().uuidString)", isDirectory: true)
        let file = GitHubService.readmeCacheFile(key: key, in: directory)
        #expect(file.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path)
        #expect(file.pathExtension == "md")
    }

    @Test("known digest and distinct ids")
    func knownDigest() {
        // printf 'wget' | shasum -a 256
        #expect(
            GitHubService.readmeCacheKey(for: "wget")
                == "readme_570e342d0e4708dab94b2025f6b928845b659b405872d824b45473c4635d7b1d")
        #expect(GitHubService.readmeCacheKey(for: "a") != GitHubService.readmeCacheKey(for: "b"))
        #expect(GitHubService.readmeCacheKey(for: "a") == GitHubService.readmeCacheKey(for: "a"))
    }

    @Test("GitHub owner and repo are kept to GitHub's alphabet")
    func ownerAndRepo() {
        let ok = GitHubService.extractGitHubRepo(from: "https://github.com/Homebrew/brew")
        #expect(ok?.owner == "Homebrew")
        #expect(ok?.repo == "brew")
        #expect(GitHubService.extractGitHubRepo(from: "https://github.com/a%20b/c") == nil)
        #expect(GitHubService.extractGitHubRepo(from: "https://github.com/../x") == nil)
        #expect(GitHubService.extractGitHubRepo(from: "https://example.org/a/b") == nil)
        #expect(GitHubService.extractGitHubRepo(from: "https://github.com/onlyowner") == nil)
    }
}
