import SwiftUI
import SwiftData

struct GroupsView: View {
    @Binding var selectedItemID: String?
    let viewMode: ContentView.ViewMode

    @Query(sort: \PackageGroup.dateCreated) private var groups: [PackageGroup]
    @Environment(\.modelContext) private var modelContext
    @Environment(BrewStore.self) private var store

    @State private var showCreateSheet: Bool = false
    @State private var selectedGroup: PackageGroup?
    @State private var newGroupName: String = ""
    @State private var newGroupIcon: String = "folder.fill"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if selectedGroup != nil {
                    Button {
                        selectedGroup = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Group", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if let group = selectedGroup {
                groupDetailView(group)
            } else {
                groupsGrid
            }
        }
        .navigationTitle(selectedGroup?.name ?? "Groups")
        .sheet(isPresented: $showCreateSheet) {
            createGroupSheet
        }
    }

    @ViewBuilder
    private var groupsGrid: some View {
        if groups.isEmpty {
            EmptyStateView(
                icon: "folder",
                title: "No Groups",
                message: "Create groups to organize your packages."
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200))], spacing: 12) {
                    ForEach(groups) { group in
                        Button {
                            selectedGroup = group
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: group.icon)
                                    .font(.title)
                                    .foregroundStyle(Color.accentColor)
                                Text(group.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("\(group.packageIDs.count) packages")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                PersistenceController.shared.deleteGroup(group)
                            } label: {
                                Label("Delete Group", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func groupDetailView(_ group: PackageGroup) -> some View {
        let items: [any BrewItem] = group.packageIDs.compactMap { store.itemByID($0) }

        if items.isEmpty {
            EmptyStateView(
                icon: "folder",
                title: "Empty Group",
                message: "Add packages to this group from the package detail view."
            )
        } else {
            ItemListView(
                items: items,
                selectedID: $selectedItemID,
                viewMode: viewMode,
                title: group.name,
                emptyIcon: "folder",
                emptyMessage: "No packages in this group"
            )
        }
    }

    @ViewBuilder
    private var createGroupSheet: some View {
        VStack(spacing: 16) {
            Text("Create Group")
                .font(.headline)
                .padding(.top)

            TextField("Group Name", text: $newGroupName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            // Icon picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                let icons = [
                    "folder.fill", "star.fill", "heart.fill", "flag.fill",
                    "bookmark.fill", "tag.fill", "tray.fill", "archivebox.fill",
                    "hammer.fill", "wrench.fill", "gearshape.fill", "terminal.fill",
                    "globe", "link", "cube.fill", "cpu.fill",
                ]

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 8) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            newGroupIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(
                                    newGroupIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                Button("Cancel") {
                    showCreateSheet = false
                    newGroupName = ""
                }
                Spacer()
                Button("Create") {
                    guard !newGroupName.isEmpty else { return }
                    _ = PersistenceController.shared.createGroup(
                        name: newGroupName, icon: newGroupIcon, color: "blue")
                    showCreateSheet = false
                    newGroupName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newGroupName.isEmpty)
            }
            .padding()
        }
        .frame(width: 350)
    }
}

// MARK: - Add to Group Sheet

struct AddToGroupSheet: View {
    let item: any BrewItem

    @Query(sort: \PackageGroup.dateCreated) private var groups: [PackageGroup]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add \(item.name) to Group")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            if groups.isEmpty {
                VStack(spacing: 8) {
                    Text("No groups yet")
                        .foregroundStyle(.secondary)
                    Text("Create a group from the Groups section first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.id) { group in
                        let isInGroup = group.packageIDs.contains(item.id)
                        Button {
                            if isInGroup {
                                PersistenceController.shared.removeFromGroup(group, packageID: item.id)
                            } else {
                                PersistenceController.shared.addToGroup(group, packageID: item.id)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: group.icon)
                                    .foregroundStyle(Color.accentColor)
                                Text(group.name)
                                Spacer()
                                if isInGroup {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 300)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: [], localization: .custom)
            }
            .padding()
        }
        .frame(width: 350)
    }
}
