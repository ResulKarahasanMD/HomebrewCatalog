import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(BrewStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var selectedItemID: String?
    @State private var viewMode: ViewMode = .grid
    @State private var searchText: String = ""

    enum ViewMode: String, CaseIterable {
        case grid, list
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            HSplitView {
                contentColumn
                    .frame(minWidth: 320, idealWidth: 480)

                detailColumn
                    .frame(minWidth: 360, idealWidth: 420)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search packages...")
        .onChange(of: searchText) { _, newValue in
            store.search(newValue)
        }
        .onChange(of: selectedItemID) { _, newID in
            // Record the visit so the History section actually fills up.
            store.selectItem(newID.flatMap { store.itemByID($0) })
        }
        .onChange(of: store.selectedSidebarSection) { _, _ in
            selectedItemID = nil
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if showsCatalogSortControls {
                    catalogSortMenu
                }

                if showsAnalyticsPeriodControls {
                    analyticsPeriodMenu
                }

                if showsViewModePicker {
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Image(systemName: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                }

                Button {
                    Task {
                        await store.refreshCatalog()
                        await store.loadInstalledPackages()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isLoading)
                .help("Refresh catalog and installed packages")
            }
        }
    }

    private var showsCatalogSortControls: Bool {
        switch store.selectedSidebarSection {
        case .formulas, .casks, .categories:
            return true
        default:
            return false
        }
    }

    private var showsAnalyticsPeriodControls: Bool {
        switch store.selectedSidebarSection {
        case .formulas, .casks, .categories, .downloads:
            return true
        default:
            return false
        }
    }

    private var showsViewModePicker: Bool {
        switch store.selectedSidebarSection {
        case .formulas, .casks, .categories, .installed, .pinned, .leaves,
             .favorites, .history, .groups:
            return true
        default:
            return false
        }
    }

    private var catalogSortMenu: some View {
        Menu {
            ForEach(CatalogSortOption.allCases, id: \.self) { option in
                Button {
                    store.setCatalogSortOption(option)
                } label: {
                    if store.catalogSortOption == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            Label(store.catalogSortOption.rawValue, systemImage: "arrow.up.arrow.down")
        }
        .disabled(store.isLoadingAnalytics)
        .help("Sort catalog listings")
    }

    private var analyticsPeriodMenu: some View {
        Menu {
            ForEach(AnalyticsTimePeriod.allCases) { period in
                Button {
                    store.setAnalyticsPeriod(period)
                } label: {
                    if store.analyticsPeriod == period {
                        Label(period.rawValue, systemImage: "checkmark")
                    } else {
                        Text(period.rawValue)
                    }
                }
            }
            Divider()
            Text(AnalyticsTimePeriod.oneYear.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            Label(store.analyticsPeriod.rawValue, systemImage: "calendar")
        }
        .disabled(store.isLoadingAnalytics)
        .help(store.analyticsPeriod.helpText)
    }

    @ViewBuilder
    private var contentColumn: some View {
        Group {
            switch store.selectedSidebarSection {
            case .discover:
                DiscoverView(selectedItemID: $selectedItemID)
            case .categories:
                CategoryBrowserView(selectedItemID: $selectedItemID, viewMode: viewMode)
            case .formulas:
                ItemListView(
                    items: store.filteredFormulas,
                    selectedID: $selectedItemID,
                    viewMode: viewMode,
                    title: "Formulae",
                    emptyIcon: "terminal",
                    emptyMessage: "No formulae found"
                )
            case .casks:
                ItemListView(
                    items: store.filteredCasks,
                    selectedID: $selectedItemID,
                    viewMode: viewMode,
                    title: "Casks",
                    emptyIcon: "macwindow",
                    emptyMessage: "No casks found"
                )
            case .downloads:
                DownloadRankingsView(selectedItemID: $selectedItemID)
            case .installed:
                InstalledView(selectedItemID: $selectedItemID, viewMode: viewMode)
            case .outdated:
                OutdatedView(selectedItemID: $selectedItemID)
            case .pinned:
                PinnedView(selectedItemID: $selectedItemID, viewMode: viewMode)
            case .leaves:
                LeavesView(selectedItemID: $selectedItemID, viewMode: viewMode)
            case .favorites:
                FavoritesView(selectedItemID: $selectedItemID, viewMode: viewMode)
            case .history:
                HistoryView(selectedItemID: $selectedItemID, viewMode: viewMode)
            case .groups:
                GroupsView(selectedItemID: $selectedItemID, viewMode: viewMode)
            case .actionHistory:
                ActionHistoryView()
            case .services:
                ServicesView()
            case .taps:
                TapsView()
            case .masApps:
                MASView()
            case .systemHealth:
                SystemHealthView()
            case .settings:
                SettingsView()
            }
        }
        .id(store.selectedSidebarSection)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selectedItemID, let item = store.itemByID(id) {
            DetailView(item: item)
        } else {
            EmptyDetailView()
        }
    }
}
