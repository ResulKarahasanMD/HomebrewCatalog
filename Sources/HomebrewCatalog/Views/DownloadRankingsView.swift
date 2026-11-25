import SwiftUI

struct DownloadRankingsView: View {
    @Binding var selectedItemID: String?

    @Environment(BrewStore.self) private var store

    @State private var filter: DownloadRankFilter = .all

    private var rows: [DownloadRankRow] {
        store.downloadRankRows(filter: filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(DownloadRankFilter.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                if store.isLoadingAnalytics {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let error = store.analyticsError, !store.hasInstallAnalytics {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()

            if store.formulas.isEmpty && store.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading catalog...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.isLoadingAnalytics && !store.hasInstallAnalytics {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading install analytics...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                EmptyStateView(
                    icon: "chart.bar",
                    title: "No Results",
                    message: "No packages match your search."
                )
            } else {
                rankingsList
            }
        }
        .navigationTitle("Downloads")
        .safeAreaInset(edge: .bottom) {
            footerBar
        }
        .task {
            await store.loadAnalyticsIfNeeded()
        }
    }

    @ViewBuilder
    private var rankingsList: some View {
        List(selection: $selectedItemID) {
            ForEach(rows) { row in
                DownloadRankRowView(row: row)
                    .tag(row.id)
            }
        }
        .listStyle(.plain)
    }

    private var footerBar: some View {
        HStack {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var footerText: String {
        let formulaCount = store.formulaDownloadRows.count
        let caskCount = store.caskDownloadRows.count
        let formulaLabel = formulaCount == 1 ? "formula" : "formulae"
        let caskLabel = caskCount == 1 ? "cask" : "casks"
        return "Showing \(InstallCountFormatter.grouped(formulaCount)) \(formulaLabel) · \(InstallCountFormatter.grouped(caskCount)) \(caskLabel)"
    }
}

// MARK: - Row

private struct DownloadRankRowView: View {
    let row: DownloadRankRow

    var body: some View {
        HStack(spacing: 12) {
            Text("\(row.rank)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if row.itemType == .cask, row.name != row.packageID {
                    Text(row.packageID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(InstallCountFormatter.grouped(row.installCount))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)

            typeBadge
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var typeBadge: some View {
        Text(row.itemType.rawValue)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(row.itemType == .cask ? .blue : .green)
            .background(
                (row.itemType == .cask ? Color.blue : Color.green).opacity(0.12),
                in: Capsule()
            )
            .frame(width: 64)
    }
}
