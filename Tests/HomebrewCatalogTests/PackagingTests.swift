import Foundation
import Testing
@testable import HomebrewCatalog

/// The app does not ship an updater: no Sparkle code is linked and no feed URL is declared.
/// Free of new symbols on purpose: these ran (and failed) against the build before the fix.
@Suite("Packaging")
struct PackagingTests {
    @Test("the test host is the app bundle")
    func hostIsApp() {
        #expect(Bundle.main.bundleIdentifier == "com.resulahmet.HomebrewCatalog")
    }

    @Test("Info.plist declares no Sparkle keys")
    func noSparkleKeys() {
        let keys = (Bundle.main.infoDictionary ?? [:]).keys.filter { $0.hasPrefix("SU") }
        #expect(keys.isEmpty, "found \(keys.sorted())")
    }

    @Test("Sparkle is neither embedded nor loaded")
    func noSparkleFramework() {
        let embedded = Bundle.main.privateFrameworksURL?.appendingPathComponent("Sparkle.framework")
        #expect(embedded.map { FileManager.default.fileExists(atPath: $0.path) } != true)
        #expect(NSClassFromString("SPUUpdater") == nil)
        #expect(NSClassFromString("SPUStandardUpdaterController") == nil)
    }
}
