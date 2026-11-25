import Foundation

struct OutputRedactor: Sendable {
    static let placeholder = "[REDACTED]"

    private static let envAssignmentPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^[A-Z_][A-Z0-9_]*=.*$"#, options: [.anchorsMatchLines])
    }()

    // The scheme is capped at 64 characters. Unbounded, a long run of letters was rescanned
    // from each of its letters, quadratic in the run's length. Behind a longer run, the match
    // starts 64 characters before "://" and still covers the credentials.
    private static let urlUserInfoPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"[a-zA-Z][a-zA-Z0-9+.-]{0,63}://[^\s@]+@[^\s]+"#,
            options: []
        )
    }()

    private static let tokenNames: [String] = [
        "GITHUB_TOKEN",
        "HOMEBREW_GITHUB_API_TOKEN",
    ]

    // Any case, so `github_token=` is caught too; a quoted value is taken whole, spaces included.
    private static let tokenValuePatterns: [NSRegularExpression] = tokenNames.map { name in
        try! NSRegularExpression(
            pattern: #"\b(\#(name))\b\s*[:=]\s*(?:"[^"]*"|'[^']*'|\S+)"#,
            options: [.caseInsensitive]
        )
    }

    /// Credentials that are recognisable without a variable name in front of them.
    private static let credentialPatterns: [(pattern: NSRegularExpression, template: String)] = [
        // An Authorization header: the scheme and everything after it.
        (try! NSRegularExpression(pattern: #"\b(Authorization)\s*:\s*[^\r\n]*"#, options: [.caseInsensitive]),
         "$1: \(placeholder)"),
        // A bearer token outside a header. A value already redacted starts with "[".
        (try! NSRegularExpression(pattern: #"\b(Bearer)\s+[^\s\[]\S*"#, options: [.caseInsensitive]),
         "$1 \(placeholder)"),
        // GitHub tokens: classic (ghp_, gho_, ghu_, ghs_, ghr_) and fine-grained.
        (try! NSRegularExpression(pattern: #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#),
         placeholder),
    ]

    func redact(_ raw: String) -> String {
        var output = raw

        output = Self.urlUserInfoPattern.stringByReplacingMatches(
            in: output,
            options: [],
            range: NSRange(output.startIndex..., in: output),
            withTemplate: Self.placeholder
        )

        for pattern in Self.tokenValuePatterns {
            output = pattern.stringByReplacingMatches(
                in: output,
                options: [],
                range: NSRange(output.startIndex..., in: output),
                withTemplate: "$1=\(Self.placeholder)"
            )
        }

        for (pattern, template) in Self.credentialPatterns {
            output = pattern.stringByReplacingMatches(
                in: output,
                options: [],
                range: NSRange(output.startIndex..., in: output),
                withTemplate: template
            )
        }

        output = Self.envAssignmentPattern.stringByReplacingMatches(
            in: output,
            options: [],
            range: NSRange(output.startIndex..., in: output),
            withTemplate: Self.placeholder
        )

        return output
    }
}
