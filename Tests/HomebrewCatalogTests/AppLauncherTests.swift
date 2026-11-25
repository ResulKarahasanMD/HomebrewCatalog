import Testing
@testable import HomebrewCatalog

@Suite("AppLauncher")
struct AppLauncherTests {
    // Tests run inside the host app's process, so this is the same check
    // AppLauncher made at launch.
    @Test("The test host is detected, so the real app is not started")
    func detectsTestHost() {
        #expect(AppLauncher.isHostingTests)
    }
}
