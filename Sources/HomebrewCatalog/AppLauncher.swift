import SwiftUI

/// Entry point. Under `xcodebuild test` the app only hosts the test bundle, so it
/// starts an empty app instead of `HomebrewCatalogApp`: no window, no `BrewStore`
/// (network fetches and `brew` runs), and no SwiftData store opened on real data.
@main
enum AppLauncher {
    @MainActor
    static func main() {
        if isHostingTests {
            TestHostApp.main()
        } else {
            HomebrewCatalogApp.main()
        }
    }

    /// Xcode sets this in the host process of every test run, XCTest or Swift Testing.
    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
