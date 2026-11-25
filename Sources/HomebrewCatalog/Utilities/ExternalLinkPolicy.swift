import Foundation

/// Decides which URLs taken from catalog JSON or README Markdown may be handed to the
/// system. Only web links pass: `file:` and app-specific schemes would let fetched content
/// open local files or drive another app's URL handler with one click.
enum ExternalLinkPolicy {
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// The URL for a homepage string, or nil when it is missing, malformed or not a web link.
    static func webURL(from string: String?) -> URL? {
        guard let string, let url = URL(string: string), isOpenable(url) else { return nil }
        return url
    }
}
