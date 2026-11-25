import SwiftUI

struct TapsView: View {
    @Environment(BrewStore.self) private var store

    @State private var showAddSheet: Bool = false
    @State private var newTapName: String = ""
    @State private var isAddingTap: Bool = false
    @State private var addTapOutput: String = ""
    @State private var tapToRemove: BrewTapInfo?

    private var feature: TapsFeatureStore { store.tapsFeature }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(feature.taps.count) taps")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if feature.isCheckingHealth {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Checking tap health on GitHub…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Tap", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(feature.isLoading || feature.isCheckingHealth)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let pausedUntil = feature.healthPausedUntil {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Tap health checks paused until \(pausedUntil.formatted(date: .omitted, time: .shortened)): GitHub's hourly request limit ran out.")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))
            }

            Divider()

            if let error = feature.error {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Taps",
                    message: error
                )
            } else if feature.isLoading && feature.taps.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading taps...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if feature.taps.isEmpty {
                EmptyStateView(
                    icon: "spigot",
                    title: "No Taps",
                    message: "Taps are third-party repositories for Homebrew packages."
                )
            } else {
                tapsList
            }
        }
        .navigationTitle("Taps")
        .task {
            await feature.loadIfNeeded()
            await feature.checkHealthIfNeeded()
        }
        .refreshable {
            await refresh()
        }
        .sheet(isPresented: $showAddSheet) {
            addTapSheet
        }
        .confirmationDialog("Remove Tap", item: $tapToRemove) { tap in
            Button("Remove \(tap.name)", role: .destructive) {
                Task { _ = await feature.remove(tap.name) }
            }
        } message: { tap in
            Text(removalMessage(for: tap))
        }
    }

    private func refresh() async {
        await feature.load()
        await feature.checkHealth()
    }

    private func removalMessage(for tap: BrewTapInfo) -> String {
        let consequence = "Removing it also removes its formulae and casks."
        switch feature.health[tap.name] {
        case .archived:
            return "\(tap.name) is archived on GitHub and gets no more updates. \(consequence)"
        case .moved(let newName):
            return "\(tap.name) moved to \(newName) on GitHub. \(consequence) You can tap the new location afterwards."
        case .missing:
            return "\(tap.name) no longer exists on GitHub. \(consequence)"
        case .healthy:
            return "\(tap.name) is healthy on GitHub. \(consequence) Remove it anyway?"
        case .rateLimited, .unknown, nil:
            return "\(tap.name)'s state on GitHub is not known. \(consequence)"
        }
    }

    @ViewBuilder
    private var tapsList: some View {
        List {
            ForEach(feature.taps) { tap in
                let health = feature.health[tap.name]
                HStack(spacing: 12) {
                    Image(systemName: tap.isOfficial ? "checkmark.seal.fill" : "spigot.fill")
                        .foregroundStyle(tap.isOfficial ? .blue : .secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(tap.name)
                                .font(.body.weight(.medium))
                            if tap.isOfficial {
                                Text("Official")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            } else if let health {
                                TapHealthBadge(health: health)
                            }
                        }
                        HStack(spacing: 12) {
                            if tap.formulaCount > 0 {
                                Label("\(tap.formulaCount) formulae", systemImage: "terminal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if tap.caskCount > 0 {
                                Label("\(tap.caskCount) casks", systemImage: "macwindow")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let remote = tap.remote {
                            Text(remote)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if !tap.isOfficial {
                        Button(role: .destructive) {
                            tapToRemove = tap
                        } label: {
                            if health?.isProblem == true {
                                Label("Remove", systemImage: "trash")
                                    .font(.caption)
                            } else {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(health?.isProblem == true ? .red : .secondary)
                        .help(health?.isProblem == true ? "Remove this tap" : "Remove this tap (asks first)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var addTapSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "spigot.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Add Tap")
                        .font(.headline)
                    Text("Enter the tap name (e.g. user/repo)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            TextField("user/repo", text: $newTapName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if !addTapOutput.isEmpty {
                ScrollView {
                    Text(addTapOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 150)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
            }

            HStack {
                Button("Cancel") { showAddSheet = false }
                    .disabled(isAddingTap)
                Spacer()
                Button {
                    let tapName = newTapName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !tapName.isEmpty else { return }
                    // Say why instead of failing inside the service with a generic message.
                    guard BrewArgumentValidator.isValid(tapName, as: .tap) else {
                        addTapOutput = "Enter the tap as user/repo (letters, digits, \".\", \"_\" and \"-\")."
                        return
                    }
                    isAddingTap = true
                    addTapOutput = ""
                    Task {
                        let result = await feature.add(tapName) { addTapOutput += $0 }
                        isAddingTap = false
                        if result?.exitCode == 0 {
                            showAddSheet = false
                            newTapName = ""
                        } else if result == nil {
                            addTapOutput += "\nCould not run brew tap."
                        }
                    }
                } label: {
                    if isAddingTap {
                        ProgressView().controlSize(.small)
                        Text("Adding...")
                    } else {
                        Text("Add Tap")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTapName.isEmpty || isAddingTap)
            }
            .padding()
        }
        .frame(width: 450)
    }
}

/// A third-party tap's GitHub state, as a small chip next to its name.
struct TapHealthBadge: View {
    let health: TapHealth

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .help(help)
    }

    private var title: String {
        switch health {
        case .healthy: "Healthy"
        case .archived: "Archived"
        case .moved(let newName): "Moved to \(newName)"
        case .missing: "Missing"
        case .rateLimited: "Not checked"
        case .unknown: "Unknown"
        }
    }

    private var symbol: String {
        switch health {
        case .healthy: "checkmark.circle"
        case .archived: "archivebox"
        case .moved: "arrow.right.circle"
        case .missing: "xmark.octagon"
        case .rateLimited: "clock"
        case .unknown: "questionmark.circle"
        }
    }

    private var tint: Color {
        switch health {
        case .healthy: .green
        case .archived: .orange
        case .moved: .indigo
        case .missing: .red
        case .rateLimited, .unknown: .secondary
        }
    }

    private var help: String {
        switch health {
        case .healthy: "The tap's repository is active on GitHub."
        case .archived: "The repository is archived: read-only, no more updates."
        case .moved(let newName): "GitHub redirects this repository to \(newName)."
        case .missing: "GitHub has no repository at this address any more."
        case .rateLimited: "Skipped: GitHub's hourly request limit ran out."
        case .unknown: "Could not check: offline, or not hosted on GitHub."
        }
    }
}
