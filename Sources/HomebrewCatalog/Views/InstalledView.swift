import SwiftUI

struct InstalledView: View {
    @Binding var selectedItemID: String?
    let viewMode: ContentView.ViewMode

    @Environment(BrewStore.self) private var store

    @State private var filter: InstalledFilter = .all

    enum InstalledFilter: String, CaseIterable {
        case all = "All"
        case formulae = "Formulae"
        case casks = "Casks"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(InstalledFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Text("\(filteredCount) packages")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

            // Partial failure (one list or leaves failed): keep the loaded data visible
            // and show the problem as a warning instead of a full-screen error.
            if store.hasCompletedInstalledRefresh, let warning = store.installedError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                Divider()
            }

            if store.isLoadingInstalled && !store.hasCompletedInstalledRefresh {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading installed packages...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !store.hasCompletedInstalledRefresh, let error = store.installedError {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Installed Packages",
                    message: error
                )
            } else if displayedFormulas.isEmpty && displayedCasks.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: filter == .all ? "No Installed Packages" : "No \(filter.rawValue) Installed",
                    message: "Install packages from the Discover or Browse sections."
                )
            } else {
                installedList
                    .redacted(reason: store.isLoadingInstalled ? .placeholder : [])
            }
        }
        .navigationTitle("Installed")
        .refreshable {
            await store.loadInstalledPackages()
        }
        .task {
            await store.loadInstalledPackagesIfNeeded()
        }
    }

    private var filteredCount: Int {
        switch filter {
        case .all: return store.installedFormulas.count + store.installedCasks.count
        case .formulae: return store.installedFormulas.count
        case .casks: return store.installedCasks.count
        }
    }

    private var displayedFormulas: [InstalledFormulaInfo] {
        guard filter != .casks else { return [] }
        return store.installedFormulas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displayedCasks: [InstalledCaskInfo] {
        guard filter != .formulae else { return [] }
        return store.installedCasks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private var installedList: some View {
        List(selection: $selectedItemID) {
            if !displayedFormulas.isEmpty {
                Section("Formulae") {
                    ForEach(displayedFormulas) { formula in
                        formulaRow(formula)
                            .tag(formula.id)
                    }
                }
            }

            if !displayedCasks.isEmpty {
                Section("Casks") {
                    ForEach(displayedCasks) { cask in
                        caskRow(cask)
                            .tag(cask.id)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func formulaRow(_ formula: InstalledFormulaInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(.green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formula.name)
                        .font(.body.weight(.medium))
                    if formula.isOutdated {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if formula.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    if formula.isLeaf {
                        Image(systemName: "leaf.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if formula.installedAsDependency && !formula.isOutdated && !formula.isPinned {
                        Image(systemName: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                    }
                }
                if let desc = formula.desc {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(formula.installedVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 2)
    }

    private func caskRow(_ cask: InstalledCaskInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow")
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cask.name)
                        .font(.body.weight(.medium))
                    if cask.isOutdated {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if let desc = cask.desc {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(cask.installedVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 2)
    }
}
