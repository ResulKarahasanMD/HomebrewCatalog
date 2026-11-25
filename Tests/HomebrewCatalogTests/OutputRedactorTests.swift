import Testing
@testable import HomebrewCatalog

@Suite("OutputRedactor")
struct OutputRedactorTests {
    let redactor = OutputRedactor()

    @Test(
        "Redacts sensitive patterns",
        arguments: [
            (
                "cloning https://user:secret@github.com/homebrew/homebrew-core.git",
                "cloning [REDACTED]"
            ),
            (
                "export GITHUB_TOKEN=ghp_abcdef1234567890",
                "export GITHUB_TOKEN=[REDACTED]"
            ),
            (
                "export HOMEBREW_GITHUB_API_TOKEN=ghp_xxxxxxxxxxxxxxxx",
                "export HOMEBREW_GITHUB_API_TOKEN=[REDACTED]"
            ),
            (
                "HOMEBREW_GITHUB_API_TOKEN=ghp_xxxxxxxxxxxxxxxx",
                "[REDACTED]"
            ),
            (
                "PATH=/opt/homebrew/bin:/usr/bin",
                "[REDACTED]"
            ),
            // A quoted value is redacted whole, not up to its first space.
            (
                "export HOMEBREW_GITHUB_API_TOKEN=\"ghp_abc def\"",
                "export HOMEBREW_GITHUB_API_TOKEN=[REDACTED]"
            ),
            (
                "  github_token=ghp_lowercasekey",
                "  github_token=[REDACTED]"
            ),
            (
                "Authorization: Bearer ghp_abcdefghijklmnopqrstuvwxyz0123456789",
                "Authorization: [REDACTED]"
            ),
            (
                "curl -H 'authorization: token abc123'",
                "curl -H 'authorization: [REDACTED]"
            ),
            (
                "using Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig now",
                "using Bearer [REDACTED] now"
            ),
            (
                "token ghp_abcdefghijklmnopqrstuvwxyz0123456789 expired",
                "token [REDACTED] expired"
            ),
            (
                "pat github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz",
                "pat [REDACTED]"
            ),
            (
                "hello world",
                "hello world"
            ),
            (
                "==> Pouring jq--1.8.0.arm64_sequoia.bottle.tar.gz",
                "==> Pouring jq--1.8.0.arm64_sequoia.bottle.tar.gz"
            ),
            (
                "visit https://brew.sh for details",
                "visit https://brew.sh for details"
            ),
        ]
    )
    func redactsSensitivePatterns(input: String, expected: String) {
        #expect(redactor.redact(input) == expected)
    }

    @Test("Redacts multiple patterns in multiline output")
    func redactsMultipleInMultiline() {
        let input = """
        cloning https://user:token@github.com/some/repo.git
        GITHUB_TOKEN=ghp_xxxxxxxx
        all good
        HOME=/Users/alice
        """
        let output = redactor.redact(input)
        #expect(output.contains("[REDACTED]"))
        #expect(!output.contains("ghp_xxxxxxxx"))
        #expect(!output.contains("user:token"))
        #expect(output.contains("all good"))
    }

    @Test("Preserves empty input")
    func preservesEmptyInput() {
        #expect(redactor.redact("") == "")
    }

    @Test("A long unbroken line is redacted in linear time")
    func longRunIsLinear() {
        // The URL pattern once rescanned the whole run from every letter: 64,000 characters
        // took 48 s on the main actor.
        let run = String(repeating: "x", count: 64_000)
        let elapsed = ContinuousClock().measure { #expect(redactor.redact(run) == run) }
        #expect(elapsed < .seconds(5))
    }

    @Test("A URL's credentials are redacted even behind a long unbroken run")
    func credentialsAfterLongRun() {
        let output = redactor.redact(String(repeating: "x", count: 100) + "https://user:pw@host/path")
        #expect(!output.contains("user:pw"))
        #expect(output.hasSuffix("[REDACTED]"))
    }

    @Test("Is idempotent under double redaction", arguments: [
        "GITHUB_TOKEN=ghp_secret123",
        "Authorization: Bearer ghp_abcdefghijklmnopqrstuvwxyz0123456789",
        "using Bearer abc.def.ghi now",
        "export HOMEBREW_GITHUB_API_TOKEN=\"ghp_abc def\"",
    ])
    func isIdempotent(input: String) {
        let once = redactor.redact(input)
        let twice = redactor.redact(once)
        #expect(once == twice)
    }
}
