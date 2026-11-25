import SwiftUI
import SwiftData

struct OutdatedView: View {
    @Binding var selectedItemID: String?

    @Environment(BrewStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var selectedForUpgrade: Set<String> = []
    @State private var upgradePlan: [OutdatedInfo] = []
    @State private var showUpgradeSheet: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Action bar
            HStack {
                Text("\(store.outdatedPackages.count) outdated packages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if !store.outdatedPackages.isEmpty {
                    Button {
                        selectedForUpgrade = Set(store.outdatedPackages.map(\.name))
                    } label: {
                        Text("Select All")
                    }
                    .buttonStyle(.borderless)

                    if !selectedForUpgrade.isEmpty {
                        Button {
                            selectedForUpgrade.removeAll()
                        } label: {
                            Text("Deselect All")
                        }
                        .buttonStyle(.borderless)
                    }

                    Button {
                        upgradePlan = upgradeTargets
                        showUpgradeSheet = true
                    } label: {
                        Label(
                            upgradeTargets.isEmpty
                                ? "Upgrade All" : "Upgrade Selected (\(upgradeTargets.count))",
                            systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(store.isExecutingAction)
                }

                Button {
                    Task { await store.loadInstalledPackages() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoadingInstalled)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if let error = store.outdatedError, store.outdatedPackages.isEmpty {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Outdated Packages",
                    message: error
                )
            } else if let error = store.installedError, store.installedCount == 0 {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Outdated Packages",
                    message: error
                )
            } else if store.isLoadingInstalled && !store.hasCompletedInstalledRefresh {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking for outdated packages...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.outdatedPackages.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Everything Up to Date",
                    message: "All installed packages are at their latest versions."
                )
            } else {
                outdatedList
                    .redacted(reason: store.isLoadingInstalled ? .placeholder : [])
            }
        }
        .navigationTitle("Outdated")
        .refreshable {
            await store.loadInstalledPackages()
        }
        .task {
            await store.loadInstalledPackagesIfNeeded()
        }
        .sheet(isPresented: $showUpgradeSheet) {
            UpgradePackagesSheet(
                plan: upgradePlan,
                upgradableCount: store.outdatedPackages.filter { !$0.isPinned }.count
            ) { notUpgraded in
                selectedForUpgrade = notUpgraded
            }
        }
    }

    /// Checked packages that are still outdated, in list order; empty means "upgrade
    /// everything". Pinned packages are left out because brew refuses to upgrade them.
    private var upgradeTargets: [OutdatedInfo] {
        store.outdatedPackages.filter { selectedForUpgrade.contains($0.name) && !$0.isPinned }
    }

    @ViewBuilder
    private var outdatedList: some View {
        List(selection: $selectedItemID) {
            ForEach(store.outdatedPackages) { pkg in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { selectedForUpgrade.contains(pkg.name) },
                        set: { isOn in
                            if isOn {
                                selectedForUpgrade.insert(pkg.name)
                            } else {
                                selectedForUpgrade.remove(pkg.name)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)

                    Image(systemName: pkg.itemType == .cask ? "macwindow" : "terminal")
                        .foregroundStyle(pkg.itemType == .cask ? .blue : .green)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(pkg.name)
                                .font(.body.weight(.medium))
                            if pkg.isPinned {
                                Label("Pinned", systemImage: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                        HStack(spacing: 4) {
                            Text(pkg.installedVersion)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(pkg.latestVersion)
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                    }

                    Spacer()

                    Button {
                        let op = BrewMutation.Op.upgrade(
                            target: .named(name: pkg.name, isCask: pkg.itemType == .cask))
                        Task {
                            _ = await store.mutations.run(BrewMutation(op), context: modelContext)
                        }
                    } label: {
                        Label("Upgrade", systemImage: "arrow.up.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(pkg.isPinned || store.isExecutingAction)
                }
                .tag(pkg.name)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Pinned View

struct PinnedView: View {
    @Binding var selectedItemID: String?
    let viewMode: ContentView.ViewMode
    @Environment(BrewStore.self) private var store

    var pinnedFormulas: [InstalledFormulaInfo] {
        store.installedFormulas.filter { $0.isPinned }
    }

    var body: some View {
        Group {
            if pinnedFormulas.isEmpty {
                EmptyStateView(
                    icon: "pin.slash",
                    title: "No Pinned Packages",
                    message: "Pin packages to prevent them from being upgraded."
                )
            } else {
                List(selection: $selectedItemID) {
                    ForEach(pinnedFormulas) { pkg in
                        HStack(spacing: 10) {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(.purple)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pkg.name)
                                    .font(.body.weight(.medium))
                                if let desc = pkg.desc {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(pkg.installedVersion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(pkg.name)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Pinned")
    }
}

// MARK: - Leaves View

struct LeavesView: View {
    @Binding var selectedItemID: String?
    let viewMode: ContentView.ViewMode
    @Environment(BrewStore.self) private var store

    var leafFormulas: [InstalledFormulaInfo] {
        store.installedFormulas.filter { $0.isLeaf }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(leafFormulas.count) leaf packages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Packages not required by any other installed package")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            if leafFormulas.isEmpty {
                EmptyStateView(
                    icon: "leaf",
                    title: "No Leaf Packages",
                    message: "Leaf packages are formulae not required by other installed packages."
                )
            } else {
                List(selection: $selectedItemID) {
                    ForEach(leafFormulas) { pkg in
                        HStack(spacing: 10) {
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(.green)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pkg.name)
                                    .font(.body.weight(.medium))
                                if let desc = pkg.desc {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(pkg.installedVersion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(pkg.name)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Leaves")
    }
}
