import SwiftUI

struct SidebarView: View {
    @Environment(BrewStore.self) private var store

    var body: some View {
        List {
            Section("Browse") {
                sidebarButton(.discover)
                sidebarButton(.categories)
                sidebarButton(.formulas)
                sidebarButton(.casks)
                sidebarButton(.downloads)
            }

            Section("Installed") {
                sidebarButton(.installed)
                sidebarButton(.outdated)
                sidebarButton(.pinned)
                sidebarButton(.leaves)
            }

            Section("Library") {
                sidebarButton(.favorites)
                sidebarButton(.history)
                sidebarButton(.groups)
                sidebarButton(.actionHistory)
            }

            Section("System") {
                sidebarButton(.services)
                sidebarButton(.taps)
                sidebarButton(.masApps)
                sidebarButton(.systemHealth)
                sidebarButton(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Homebrew")
    }

    private func sidebarButton(_ section: SidebarSection) -> some View {
        let isSelected = store.selectedSidebarSection == section
        let badge = section.badgeCount(from: store) ?? 0

        return Button {
            store.selectedSidebarSection = section
        } label: {
            HStack {
                Label(section.rawValue, systemImage: section.icon)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
    }
}
