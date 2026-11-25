import SwiftUI

struct DiscoverView: View {
    @Binding var selectedItemID: String?
    @Environment(BrewStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Status bar
                if store.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading catalog...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                } else if let error = store.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await store.refreshCatalog() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal)
                }

                // Quick stats
                if !store.formulas.isEmpty || !store.casks.isEmpty {
                    statsBar
                }

                // Popular installs
                if !store.featuredItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Popular")
                                .font(.title2.bold())
                            Text(popularSectionCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(store.featuredItems, id: \.id) { item in
                                    FeaturedCard(
                                        item: item,
                                        isSelected: selectedItemID == item.id,
                                        installCountLabel: store.installCountLabel(for: item)
                                    )
                                        .onTapGesture {
                                            selectedItemID = item.id
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // Recently updated
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recently Updated")
                        .font(.title2.bold())
                        .padding(.horizontal)

                    let recentItems = recentlyUpdatedItems
                    if recentItems.isEmpty {
                        EmptyStateView(
                            icon: "clock",
                            title: "Loading...",
                            message: "Recent items will appear once the catalog loads."
                        )
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 200, maximum: 280))],
                            spacing: 12
                        ) {
                            ForEach(recentItems, id: \.id) { item in
                                GridItemCard(
                                    item: item,
                                    isSelected: selectedItemID == item.id,
                                    installStatus: store.installStatus(for: item),
                                    installCountLabel: store.installCountLabel(for: item)
                                )
                                .onTapGesture {
                                    selectedItemID = item.id
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Outdated packages notification
                if store.outdatedCount > 0 {
                    outdatedBanner
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Discover")
    }

    private var popularSectionCaption: String {
        if store.hasInstallAnalytics {
            return "Top installs · \(store.analyticsPeriod.rawValue.lowercased())"
        }
        return "Curated picks while install analytics load"
    }

    private var recentlyUpdatedItems: [any BrewItem] {
        let formulas = store.formulas
            .filter { !$0.deprecated && !$0.disabled }
            .prefix(5)
        let casks = store.casks
            .filter { !$0.deprecated && !$0.disabled }
            .prefix(5)
        let combined: [any BrewItem] = Array(formulas) + Array(casks)
        return Array(combined.prefix(10))
    }

    @ViewBuilder
    private var statsBar: some View {
        // An adaptive grid wraps tiles onto a new row in a narrow content column;
        // a fixed HStack squeezed them until each label broke letter by letter.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .leading)],
            alignment: .leading,
            spacing: 12
        ) {
            StatCard(
                icon: "terminal",
                label: "Formulae",
                value: "\(store.formulas.count)",
                color: .green
            )
            StatCard(
                icon: "macwindow",
                label: "Casks",
                value: "\(store.casks.count)",
                color: .blue
            )
            if store.installedCount > 0 {
                StatCard(
                    icon: "checkmark.circle.fill",
                    label: "Installed",
                    value: "\(store.installedCount)",
                    color: .purple
                )
            }
            if store.outdatedCount > 0 {
                StatCard(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Outdated",
                    value: "\(store.outdatedCount)",
                    color: .orange
                )
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var outdatedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.outdatedCount) packages have updates available")
                    .font(.subheadline.bold())
                Text("Go to the Outdated section to upgrade them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline.bold())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FeaturedCard: View {
    let item: any BrewItem
    let isSelected: Bool
    var installCountLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 8)
                .fill(item.itemType == .cask
                    ? Color.blue.gradient
                    : Color.green.gradient)
                .frame(width: 200, height: 100)
                .overlay {
                    Image(
                        systemName: item.itemType == .cask
                            ? "macwindow" : "terminal.fill"
                    )
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.8))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let installCountLabel {
                    Text(installCountLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let desc = item.desc {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(8)
        }
        .frame(width: 200)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
    }
}
