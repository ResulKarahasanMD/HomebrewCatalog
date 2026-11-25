import SwiftUI

struct ItemListView: View {
    let items: [any BrewItem]
    @Binding var selectedID: String?
    let viewMode: ContentView.ViewMode
    let title: String
    let emptyIcon: String
    let emptyMessage: String

    @Environment(BrewStore.self) private var store

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(
                    icon: emptyIcon,
                    title: "No Results",
                    message: emptyMessage
                )
            } else {
                switch viewMode {
                case .grid:
                    gridView
                case .list:
                    listView
                }
            }
        }
        .navigationTitle(title)
    }

    @ViewBuilder
    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280))],
                spacing: 12
            ) {
                ForEach(items, id: \.id) { item in
                    GridItemCard(
                        item: item,
                        isSelected: selectedID == item.id,
                        installStatus: store.installStatus(for: item),
                        installCountLabel: store.installCountLabel(for: item)
                    )
                    .onTapGesture {
                        selectedID = item.id
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var listView: some View {
        List(selection: $selectedID) {
            ForEach(items, id: \.id) { item in
                ListItemRow(
                    item: item,
                    installStatus: store.installStatus(for: item),
                    installCountLabel: store.installCountLabel(for: item)
                )
                .tag(item.id)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Grid Item Card

struct GridItemCard: View {
    let item: any BrewItem
    let isSelected: Bool
    let installStatus: InstallStatus
    var installCountLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon area
            RoundedRectangle(cornerRadius: 8)
                .fill(item.itemType == .cask
                    ? Color.blue.opacity(0.15)
                    : Color.green.opacity(0.15))
                .frame(height: 70)
                .overlay {
                    Image(systemName: item.itemType == .cask ? "macwindow" : "terminal.fill")
                        .font(.title)
                        .foregroundStyle(item.itemType == .cask ? .blue : .green)
                }
                .overlay(alignment: .topTrailing) {
                    statusBadge
                        .padding(6)
                }

            VStack(alignment: .leading, spacing: 4) {
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

                HStack {
                    if let version = item.version {
                        Text(version)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if item.deprecated {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(8)
        }
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3), lineWidth: isSelected ? 2 : 0.5)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch installStatus {
        case .notInstalled:
            EmptyView()
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .installedAsDependency:
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.teal)
        case .outdated:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
        case .pinned:
            Image(systemName: "pin.fill")
                .font(.caption)
                .foregroundStyle(.purple)
        }
    }
}

// MARK: - List Item Row

struct ListItemRow: View {
    let item: any BrewItem
    let installStatus: InstallStatus
    var installCountLabel: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.itemType == .cask ? "macwindow" : "terminal")
                .foregroundStyle(item.itemType == .cask ? .blue : .green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.medium))

                    statusIndicator
                }

                if let desc = item.desc {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let installCountLabel {
                    Text(installCountLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.deprecated {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let version = item.version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch installStatus {
        case .notInstalled:
            EmptyView()
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .installedAsDependency:
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption2)
                .foregroundStyle(.teal)
        case .outdated:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .pinned:
            Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.purple)
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
