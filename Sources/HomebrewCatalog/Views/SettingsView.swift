import SwiftUI

struct SettingsView: View {
    @Environment(BrewStore.self) private var store

    // Preferences — defaults are registered centrally in HomebrewCatalogApp.init()
    @AppStorage("customBrewPath") private var customBrewPath: String?
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval: Int?
    @AppStorage("cacheDurationDays") private var cacheDurationDays: Int?
    @AppStorage("appTheme") private var appTheme: String?
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool?

    @State private var detectedBrewPath: String = ""
    @State private var isValidBrewPath: Bool = true
    @State private var cacheSize: String = "Calculating..."
    @State private var isDetecting: Bool = false
    @State private var detectError: String?

    var body: some View {
        Form {
            brewPathSection
            appearanceSection
            generalSection
            cacheSection
            menuBarSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            updateCacheSize()
        }
        .task {
            await detectBrewPathOnOpen()
        }
    }

    // MARK: - Brew Path

    @ViewBuilder
    private var brewPathSection: some View {
        Section {
            HStack {
                TextField("Homebrew path", text: customBrewPathBinding, prompt: Text("Auto-detect"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customBrewPath ?? "") { _, newValue in
                        validateBrewPath(newValue)
                        Task {
                            await BrewProcessService.shared.invalidateBrewPath()
                            if !newValue.isEmpty, isValidBrewPath {
                                await BrewProcessService.shared.setCustomBrewPath(newValue)
                            }
                        }
                    }

                if !(customBrewPath ?? "").isEmpty {
                    Image(systemName: isValidBrewPath ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isValidBrewPath ? .green : .red)
                }

                if isDetecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Auto-detect") {
                        detectBrewPath()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let err = detectError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !detectedBrewPath.isEmpty && (customBrewPath ?? "").isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("Detected: \(detectedBrewPath)")
                        .font(.caption)
                }
            }
        } header: {
            Text("Homebrew Path")
        } footer: {
            Text("Leave empty to auto-detect. Supported paths: /opt/homebrew/bin/brew (Apple Silicon), /usr/local/bin/brew (Intel). Any other path must be the bin/brew of a Homebrew prefix that only you or an administrator can modify.")
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: appThemeBinding) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - General

    @ViewBuilder
    private var generalSection: some View {
        Section("General") {
            Picker("Auto-refresh interval", selection: autoRefreshIntervalBinding) {
                Text("Disabled").tag(0)
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("1 hour").tag(60)
                Text("2 hours").tag(120)
                Text("6 hours").tag(360)
                Text("12 hours").tag(720)
                Text("Daily").tag(1440)
            }

            Picker("Cache duration", selection: cacheDurationDaysBinding) {
                Text("1 day").tag(1)
                Text("3 days").tag(3)
                Text("7 days").tag(7)
                Text("14 days").tag(14)
            }
        }
    }

    // MARK: - Cache

    @ViewBuilder
    private var cacheSection: some View {
        Section("Cache") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cache Size")
                        .font(.body)
                    Text(cacheSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    Task {
                        try? await CatalogCache.shared.clearCache()
                        try? await InstalledStateCache.shared.clear()
                        updateCacheSize()
                    }
                } label: {
                    Label("Clear Cache", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Menu Bar

    @ViewBuilder
    private var menuBarSection: some View {
        Section("Menu Bar") {
            Toggle("Show menu bar extra", isOn: Binding(
                get: { showMenuBarExtra ?? true },
                set: { newValue in
                    showMenuBarExtra = newValue
                    UserDefaults.standard.set(newValue, forKey: "showMenuBarExtra")
                }
            ))

            if showMenuBarExtra ?? true {
                Text("Shows outdated package count in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Build", value: "2026.04.22")

            HStack {
                Spacer()
                Text("Homebrew Catalog")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var customBrewPathBinding: Binding<String> {
        Binding(
            get: { customBrewPath ?? "" },
            set: { customBrewPath = $0 }
        )
    }

    private var appThemeBinding: Binding<String> {
        Binding(
            get: { appTheme ?? "system" },
            set: { appTheme = $0 }
        )
    }

    private var autoRefreshIntervalBinding: Binding<Int> {
        Binding(
            get: { autoRefreshInterval ?? 0 },
            set: { autoRefreshInterval = $0 }
        )
    }

    private var cacheDurationDaysBinding: Binding<Int> {
        Binding(
            get: { cacheDurationDays ?? 1 },
            set: { cacheDurationDays = $0 }
        )
    }

    private func validateBrewPath(_ path: String) {
        if path.isEmpty {
            isValidBrewPath = true
        } else {
            isValidBrewPath = BrewProcessService.isAllowedBrewPath(path, customOverride: path)
        }
    }

    private func detectBrewPathOnOpen() async {
        await BrewProcessService.shared.clearInvalidCustomBrewPathIfNeeded()
        await BrewProcessService.shared.invalidateBrewPath()
        if let path = await BrewProcessService.shared.currentBrewPath() {
            detectedBrewPath = path
            if (customBrewPath ?? "").isEmpty {
                customBrewPath = path
                isValidBrewPath = true
            }
            detectError = nil
        } else if (customBrewPath ?? "").isEmpty {
            detectError = "Homebrew not found. Install Homebrew or enter a path manually."
        }
    }

    private func detectBrewPath() {
        isDetecting = true
        detectError = nil
        Task {
            // A valid override is always resolved first, so drop it to really search
            // the standard locations; put it back if nothing is found there.
            let previousOverride = UserDefaults.standard.string(forKey: "customBrewPath")
            await BrewProcessService.shared.clearCustomBrewPath()
            if let path = await BrewProcessService.shared.currentBrewPath() {
                await BrewProcessService.shared.setCustomBrewPath(path)
                await MainActor.run {
                    customBrewPath = path
                    detectedBrewPath = path
                    isValidBrewPath = true
                    detectError = nil
                    isDetecting = false
                }
            } else {
                if let previousOverride, !previousOverride.isEmpty {
                    await BrewProcessService.shared.setCustomBrewPath(previousOverride)
                }
                await MainActor.run {
                    detectError = "Homebrew not found. Install Homebrew or enter a path manually."
                    isDetecting = false
                }
            }
        }
    }

    private func updateCacheSize() {
        let bytes = CatalogCache.shared.cacheSize
        cacheSize = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
