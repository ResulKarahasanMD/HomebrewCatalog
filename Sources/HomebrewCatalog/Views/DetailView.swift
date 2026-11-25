import SwiftUI
import SwiftData

struct DetailView: View {
    let item: any BrewItem
    @Environment(BrewStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: DetailTab = .overview
    @State private var readmeContent: String?
    @State private var isLoadingREADME: Bool = false
    @State private var readmeError: String?
    @State private var readmeTask: Task<Void, Never>?
    @State private var isFavorite: Bool = false
    @State private var showActionSheet: Bool = false
    @State private var actionType: PackageActionSheet.ActionType = .install
    @State private var showAddToGroupSheet: Bool = false

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case readme = "README"
        case dependencies = "Dependencies"
    }

    private var installStatus: InstallStatus {
        store.installStatus(for: item)
    }

    private var isItemInstalled: Bool {
        store.isInstalled(item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                warningBanners
                tabPicker
                tabContent
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
        .onAppear {
            checkFavoriteStatus()
            if selectedTab == .readme {
                loadREADME()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .readme {
                loadREADME()
            }
        }
        .onChange(of: item.id) { _, _ in
            // Cancel an in-flight fetch so the previous package's README can't
            // land in this package's view.
            readmeTask?.cancel()
            readmeTask = nil
            selectedTab = .overview
            readmeContent = nil
            readmeError = nil
            isLoadingREADME = false
            checkFavoriteStatus()
        }
        .sheet(isPresented: $showActionSheet) {
            PackageActionSheet(item: item, actionType: actionType)
                .environment(store)
                .modelContainer(modelContext.container)
        }
        .sheet(isPresented: $showAddToGroupSheet) {
            AddToGroupSheet(item: item)
                .modelContainer(modelContext.container)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(item.itemType == .cask
                    ? Color.blue.gradient
                    : Color.green.gradient)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: item.itemType == .cask ? "macwindow" : "terminal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.name)
                        .font(.title.bold())
                    installStatusBadge
                }

                if let desc = item.desc {
                    Text(desc)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let version = item.version {
                        MetadataChip(icon: "tag", text: version)
                    }
                    if let license = item.license {
                        MetadataChip(icon: "doc.text", text: license)
                    }
                    MetadataChip(
                        icon: item.itemType == .cask ? "macwindow" : "terminal",
                        text: item.itemType.rawValue)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var installStatusBadge: some View {
        switch installStatus {
        case .notInstalled:
            EmptyView()
        case .installed(let version):
            Label(version, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.1), in: Capsule())
        case .installedAsDependency(let version):
            Label("\(version) (dependency)", systemImage: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.teal)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.teal.opacity(0.1), in: Capsule())
        case .outdated(let installed, let latest):
            Label("\(installed) → \(latest)", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.1), in: Capsule())
        case .pinned(let version):
            Label("\(version) (pinned)", systemImage: "pin.fill")
                .font(.caption)
                .foregroundStyle(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.purple.opacity(0.1), in: Capsule())
        }
    }

    // MARK: - Warning Banners

    @ViewBuilder
    private var warningBanners: some View {
        if item.deprecated {
            WarningBanner(
                icon: "exclamationmark.triangle.fill",
                title: "Deprecated",
                message: item.deprecationReason ?? "This package has been deprecated.",
                color: .orange
            )
        }
        if item.disabled {
            WarningBanner(
                icon: "xmark.octagon.fill",
                title: "Disabled",
                message: "This package has been disabled and cannot be installed.",
                color: .red
            )
        }
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            OverviewTab(item: item)
        case .readme:
            READMETab(
                item: item, content: readmeContent,
                isLoading: isLoadingREADME, error: readmeError)
        case .dependencies:
            DependenciesTab(item: item)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarButtons: some View {
        // Favorite toggle
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite ? .red : .secondary)
        }
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")

        // Add to group
        Button {
            showAddToGroupSheet = true
        } label: {
            Image(systemName: "folder.badge.plus")
        }
        .help("Add to Group")

        // Action buttons based on install status
        if isItemInstalled {
            Menu {
                Button {
                    actionType = .upgrade
                    showActionSheet = true
                } label: {
                    Label("Upgrade", systemImage: "arrow.up.circle")
                }

                Button {
                    actionType = .reinstall
                    showActionSheet = true
                } label: {
                    Label("Reinstall", systemImage: "arrow.clockwise")
                }

                Divider()

                if item.itemType == .formula {
                    let isPinned: Bool = {
                        if case .pinned = installStatus { return true }
                        return false
                    }()
                    Button {
                        let name = item.brewIdentifier
                        Task {
                            _ = await store.mutations.run(
                                BrewMutation(isPinned ? .unpin(name: name) : .pin(name: name)),
                                context: modelContext
                            )
                        }
                    } label: {
                        Label(isPinned ? "Unpin" : "Pin",
                              systemImage: isPinned ? "pin.slash" : "pin")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    actionType = .uninstall
                    showActionSheet = true
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        } else {
            Button {
                actionType = .install
                showActionSheet = true
            } label: {
                Label("Install", systemImage: "arrow.down.circle.fill")
            }
            .disabled(item.disabled)
        }

        // Homepage
        if let url = ExternalLinkPolicy.webURL(from: item.homepage) {
            Link(destination: url) {
                Image(systemName: "globe")
            }
            .help("Open homepage")
        }
    }

    // MARK: - Helpers

    private func loadREADME() {
        guard readmeContent == nil && !isLoadingREADME else { return }
        isLoadingREADME = true
        readmeError = nil
        readmeTask?.cancel()
        readmeTask = Task {
            do {
                let markdown = try await GitHubService.shared.fetchREADME(for: item)
                guard !Task.isCancelled else { return }
                readmeContent = markdown
            } catch {
                guard !Task.isCancelled else { return }
                readmeError = error.localizedDescription
            }
            isLoadingREADME = false
        }
    }

    private func checkFavoriteStatus() {
        isFavorite = PersistenceController.shared.isFavorite(id: item.id)
    }

    private func toggleFavorite() {
        isFavorite = PersistenceController.shared.toggleFavorite(
            id: item.id, name: item.name, itemType: item.itemType)
    }
}

// MARK: - Supporting Views

struct MetadataChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

struct WarningBanner: View {
    let icon: String
    let title: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(color)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
