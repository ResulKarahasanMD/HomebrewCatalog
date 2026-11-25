import SwiftUI

struct MASView: View {
    @Environment(BrewStore.self) private var store

    @State private var searchQuery: String = ""
    @State private var searchResults: [MASAppInfo] = []
    @State private var isSearching: Bool = false
    @State private var selectedTab: MASTab = .installed
    @State private var updateError: String?

    enum MASTab: String, CaseIterable {
        case installed = "Installed"
        case outdated = "Outdated"
        case search = "Search"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(MASTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()

                if selectedTab == .search {
                    TextField("Search Mac App Store...", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 250)
                        .onSubmit { performSearch() }
                }

                Button {
                    Task { await store.loadMASApps() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoadingMAS)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if let masError = store.masError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(masError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                Divider()
            }

            if !store.isMASAvailable {
                masNotAvailable
            } else if store.isLoadingMAS && store.masApps.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading Mac App Store apps...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedTab {
                case .installed:
                    installedApps
                case .outdated:
                    outdatedApps
                case .search:
                    searchResultsList
                }
            }
        }
        .navigationTitle("Mac App Store")
        .onAppear {
            Task { await store.loadMASApps() }
        }
        .alert("Update Failed", item: $updateError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
    }

    @ViewBuilder
    private var masNotAvailable: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("mas Not Installed")
                .font(.title3.bold())
            Text("Install mas to manage Mac App Store apps from Homebrew Catalog.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("Run:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("brew install mas")
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install mas", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var installedApps: some View {
        if store.masApps.isEmpty {
            EmptyStateView(
                icon: "app.badge",
                title: "No Apps Found",
                message: "No Mac App Store apps detected."
            )
        } else {
            List {
                ForEach(store.masApps) { app in
                    masAppRow(app)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var outdatedApps: some View {
        if store.masOutdated.isEmpty {
            EmptyStateView(
                icon: "checkmark.circle",
                title: "All Apps Up to Date",
                message: "All Mac App Store apps are at their latest versions."
            )
        } else {
            List {
                ForEach(store.masOutdated) { app in
                    HStack(spacing: 10) {
                        Image(systemName: "app.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.body.weight(.medium))
                            HStack(spacing: 4) {
                                Text(app.currentVersion)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(app.availableVersion ?? "")
                                    .foregroundStyle(.orange)
                            }
                            .font(.caption)
                        }

                        Spacer()

                        Button {
                            Task {
                                do {
                                    _ = try await MASService.shared.upgrade(appID: app.appID)
                                    await store.loadMASApps()
                                } catch {
                                    // `mas upgrade` typically fails without root; tell the user instead of silently refreshing.
                                    updateError = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("Update", systemImage: "arrow.up.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if isSearching {
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty && !searchQuery.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Results",
                message: "No apps found for \"\(searchQuery)\"."
            )
        } else if searchResults.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "Search Mac App Store",
                message: "Enter a search query to find apps."
            )
        } else {
            List {
                ForEach(searchResults) { app in
                    masAppRow(app)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func masAppRow(_ app: MASAppInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "app.fill")
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                Text("ID: \(app.appID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !app.currentVersion.isEmpty {
                Text(app.currentVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            do {
                searchResults = try await MASService.shared.search(query: searchQuery)
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }
}
