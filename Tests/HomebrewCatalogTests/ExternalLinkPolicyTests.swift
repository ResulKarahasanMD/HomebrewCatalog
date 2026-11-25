import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("ExternalLinkPolicy")
struct ExternalLinkPolicyTests {
    @Test("web links are openable", arguments: [
        "https://example.org", "http://example.org/path?q=1", "HTTPS://Example.org/",
    ])
    func webLinks(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(ExternalLinkPolicy.isOpenable(url))
        #expect(ExternalLinkPolicy.webURL(from: string) == url)
    }

    @Test("homepageSchemeAllowList: other schemes and host-less links produce no link", arguments: [
        "file:///etc/hosts", "x-custom://a", "javascript:alert(1)", "smb://server/share",
        "x-apple.systempreferences:com.apple.preference.security", "mailto:a@example.org",
        "https:///nohost", "docs/README.md", "//example.org/x", "",
    ])
    func otherSchemes(_ string: String) {
        #expect(ExternalLinkPolicy.webURL(from: string) == nil)
        if let url = URL(string: string) {
            #expect(!ExternalLinkPolicy.isOpenable(url))
        }
    }

    @Test("a missing homepage produces no link")
    func missingHomepage() {
        #expect(ExternalLinkPolicy.webURL(from: nil) == nil)
    }
}
