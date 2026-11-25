import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Binding var selectedItemID: String?
    let viewMode: ContentView.ViewMode

    @Query(sort: \FavoriteItem.dateAdded, order: .reverse) private var favorites: [FavoriteItem]
    @Environment(BrewStore.self) private var store

    var body: some View {
        Group {
            let items: [any BrewItem] = favorites.compactMap { store.itemByID($0.id) }
            if items.isEmpty {
                EmptyStateView(
                    icon: "heart",
                    title: "No Favorites",
                    message: "Mark packages as favorites from the detail view."
                )
            } else {
                ItemListView(
                    items: items,
                    selectedID: $selectedItemID,
                    viewMode: viewMode,
                    title: "Favorites",
                    emptyIcon: "heart",
                    emptyMessage: "No favorites yet"
                )
            }
        }
        .navigationTitle("Favorites")
    }
}

struct HistoryView: View {
    @Binding var selectedItemID: String?
    let viewMode: ContentView.ViewMode

    @Query(sort: \HistoryItem.lastViewed, order: .reverse) private var historyItems: [HistoryItem]
    @Environment(BrewStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if !historyItems.isEmpty {
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        PersistenceController.shared.clearHistory()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider()
            }

            let items: [any BrewItem] = historyItems.compactMap { store.itemByID($0.id) }
            if items.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "No History",
                    message: "Recently viewed packages will appear here."
                )
            } else {
                ItemListView(
                    items: items,
                    selectedID: $selectedItemID,
                    viewMode: viewMode,
                    title: "History",
                    emptyIcon: "clock",
                    emptyMessage: "No history yet"
                )
            }
        }
        .navigationTitle("History")
    }
}
