import SwiftUI

struct CategoryBrowserView: View {
    @Binding var selectedItemID: String?
    let viewMode: ContentView.ViewMode

    @Environment(BrewStore.self) private var store
    @State private var selectedCategory: Category?

    var body: some View {
        VStack(spacing: 0) {
            if let category = selectedCategory {
                // Category detail view
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            selectedCategory = nil
                        } label: {
                            Label("Categories", systemImage: "chevron.left")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        Text("\(store.categoryItems(for: category).count) packages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    Divider()

                    ItemListView(
                        items: store.categoryItems(for: category),
                        selectedID: $selectedItemID,
                        viewMode: viewMode,
                        title: category.rawValue,
                        emptyIcon: category.icon,
                        emptyMessage: "No packages in this category"
                    )
                }
            } else {
                // Category grid
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 200))],
                        spacing: 12
                    ) {
                        ForEach(Category.allCases, id: \.self) { category in
                            CategoryCard(
                                category: category,
                                count: store.itemCount(for: category)
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(selectedCategory?.rawValue ?? "Categories")
    }

}

struct CategoryCard: View {
    let category: Category
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 36)

                Text(category.rawValue)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text("\(count) packages")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .frame(height: 120)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
