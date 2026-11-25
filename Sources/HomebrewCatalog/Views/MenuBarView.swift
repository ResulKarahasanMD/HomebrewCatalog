import SwiftUI

struct MenuBarView: View {
    @Environment(BrewStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.outdatedPackages.isEmpty {
                Text("All packages up to date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                Text("\(store.outdatedPackages.count) Outdated")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Divider()

                ForEach(store.outdatedPackages.prefix(10)) { pkg in
                    HStack(spacing: 6) {
                        Image(systemName: pkg.itemType == .cask ? "macwindow" : "terminal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 14)

                        Text(pkg.name)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        Text("\(pkg.installedVersion) → \(pkg.latestVersion)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }

                if store.outdatedPackages.count > 10 {
                    Text("... and \(store.outdatedPackages.count - 10) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                }
            }

            Divider()

            Button {
                Task { await store.loadInstalledPackages() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Divider()

            Button("Open Homebrew Catalog") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title.contains("Homebrew") || $0.isKeyWindow }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    // Open main window
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}
