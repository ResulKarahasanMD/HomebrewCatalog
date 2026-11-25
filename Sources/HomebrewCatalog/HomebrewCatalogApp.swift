import SwiftUI
import SwiftData

/// Launched by `AppLauncher`, which skips it when the process only hosts tests.
struct HomebrewCatalogApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: HomebrewCatalogAppDelegate

    let container: ModelContainer

    @State private var store = BrewStore()
    @AppStorage("appTheme") private var appTheme: String?
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool?
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval: Int?

    init() {
        // Register default preference values exactly once at launch so that
        // @AppStorage across multiple scenes (WindowGroup, Settings, MenuBarExtra)
        // reads a consistent baseline without fighting over write ordering.
        UserDefaults.standard.register(defaults: [
            "showMenuBarExtra": true,
            "appTheme": "system",
            "autoRefreshInterval": 0,
            "cacheDurationDays": 1,
            "customBrewPath": "",
        ])

        do {
            container = try PersistenceController.makeContainer()
            // Share the single container with PersistenceController. Two containers on
            // the same store meant writes through one (favorites, history, group
            // deletion) were invisible to @Query views bound to the other.
            PersistenceController.configure(container: container)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .frame(minWidth: 900, minHeight: 650)
                .environment(store)
                .onAppear {
                    applyTheme()
                    store.updateAutoRefreshSchedule()
                }
                .onChange(of: appTheme) { _, _ in
                    applyTheme()
                }
                .onChange(of: autoRefreshInterval) { _, _ in
                    store.updateAutoRefreshSchedule()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            // ⌘R from the BrewVault prototype; the only other refresh control lives
            // on the Discover screen.
            CommandGroup(after: .toolbar) {
                Button("Refresh Catalog") {
                    Task { await store.refreshCatalog() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isLoading)
            }
        }

        Settings {
            SettingsView()
                .modelContainer(container)
                .environment(store)
        }

        MenuBarExtra("Homebrew Catalog", systemImage: menuBarIcon, isInserted: menuBarExtraBinding) {
            MenuBarView()
                .environment(store)
                .modelContainer(container)
        }
    }

    private var menuBarIcon: String {
        store.outdatedCount > 0 ? "mug.fill" : "mug"
    }

    private var menuBarExtraBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarExtra ?? true },
            set: { showMenuBarExtra = $0 }
        )
    }

    private func applyTheme() {
        switch appTheme ?? "system" {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}
