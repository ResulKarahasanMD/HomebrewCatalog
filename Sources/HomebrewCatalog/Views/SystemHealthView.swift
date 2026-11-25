import SwiftUI
import SwiftData

struct SystemHealthView: View {
    @Environment(BrewStore.self) private var store

    @State private var cleanupOutput: String = ""
    @State private var autoremoveOutput: String = ""
    @State private var showCleanupConfirmation: Bool = false
    @State private var showAutoremoveConfirmation: Bool = false

    private var maintenance: MaintenanceFeatureStore { store.maintenance }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = store.installedError {
                    installedErrorBanner(error)
                }

                if let error = maintenance.error {
                    maintenanceErrorBanner(error)
                }

                brewInfoCard
                quickActionsSection
                doctorSection
                cleanupSection
                autoremoveSection
            }
            .padding(20)
        }
        .navigationTitle("System Health")
        .task {
            await store.loadBrewEnvironment()
        }
        .confirmationDialog(
            "Run Cleanup?",
            isPresented: $showCleanupConfirmation
        ) {
            Button("Run Cleanup", role: .destructive) {
                cleanupOutput = ""
                Task { await maintenance.runCleanup { cleanupOutput += $0 } }
            }
        } message: {
            Text(cleanupConfirmationMessage)
        }
        .confirmationDialog(
            "Remove Orphaned Packages?",
            isPresented: $showAutoremoveConfirmation
        ) {
            Button("Remove Orphans", role: .destructive) {
                autoremoveOutput = ""
                Task { await maintenance.runAutoremove { autoremoveOutput += $0 } }
            }
        } message: {
            Text(autoremoveConfirmationMessage)
        }
    }

    private var cleanupConfirmationMessage: String {
        guard let preview = maintenance.cleanupPreview else { return "" }
        let freed = preview.freed.map { ", freeing about \($0)" } ?? ""
        return "This removes the \(preview.items.count) items in the preview\(freed)."
    }

    private var autoremoveConfirmationMessage: String {
        guard let preview = maintenance.autoremovePreview else { return "" }
        return "This uninstalls \(preview.formulae.joined(separator: ", ")), which no installed package needs."
    }

    @ViewBuilder
    private func installedErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func maintenanceErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Brew Info Card

    @ViewBuilder
    private var brewInfoCard: some View {
        if let env = store.brewEnvironment {
            GroupBox("Homebrew Environment") {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    infoCell(label: "Version", value: env.version, icon: "tag")
                    infoCell(label: "Prefix", value: env.prefix, icon: "folder")
                    infoCell(label: "Cellar", value: env.cellar, icon: "archivebox")
                    infoCell(label: "CPU", value: env.cpu, icon: "cpu")
                    infoCell(label: "macOS", value: env.macOS, icon: "desktopcomputer")
                    infoCell(
                        label: "Installed",
                        value: "\(store.installedFormulas.count) formulae, \(store.installedCasks.count) casks",
                        icon: "shippingbox"
                    )
                }
                .padding(.top, 4)
            }
        } else {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading Homebrew environment...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func infoCell(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsSection: some View {
        GroupBox("Quick Actions") {
            HStack(spacing: 12) {
                ActionButton(
                    title: "Run Doctor",
                    icon: "stethoscope",
                    color: .blue,
                    isLoading: maintenance.isRunningDoctor
                ) {
                    Task { await maintenance.runDoctor() }
                }

                ActionButton(
                    title: "Cleanup",
                    icon: "trash",
                    color: .orange,
                    isLoading: maintenance.isLoadingCleanupPreview
                ) {
                    cleanupOutput = ""
                    Task { await maintenance.loadCleanupPreview() }
                }

                ActionButton(
                    title: "Autoremove",
                    icon: "leaf.arrow.circlepath",
                    color: .green,
                    isLoading: maintenance.isLoadingAutoremovePreview
                ) {
                    autoremoveOutput = ""
                    Task { await maintenance.loadAutoremovePreview() }
                }

                ActionButton(
                    title: "Refresh",
                    icon: "arrow.clockwise",
                    color: .purple,
                    isLoading: store.isLoadingInstalled
                ) {
                    Task { await store.refreshSystemHealth() }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Doctor

    @ViewBuilder
    private var doctorSection: some View {
        if !maintenance.doctorOutput.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Doctor Output", systemImage: "stethoscope")
                            .font(.subheadline.bold())
                        Spacer()
                        Button("Clear") {
                            maintenance.clearDoctorOutput()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    ScrollView {
                        Text(maintenance.doctorOutput)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 250)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Cleanup

    @ViewBuilder
    private var cleanupSection: some View {
        if maintenance.cleanupPreview != nil || !cleanupOutput.isEmpty || maintenance.isRunningCleanup {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Cleanup Preview", systemImage: "trash")
                            .font(.subheadline.bold())
                        Spacer()
                        Button("Clear") {
                            maintenance.clearCleanupPreview()
                            cleanupOutput = ""
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(maintenance.isRunningCleanup)
                    }

                    if let preview = maintenance.cleanupPreview {
                        cleanupPreviewBody(preview)
                    } else {
                        runOutput(cleanupOutput, isRunning: maintenance.isRunningCleanup)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cleanupPreviewBody(_ preview: CleanupPreview) -> some View {
        if preview.isEmpty {
            Label("Nothing to clean up.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(preview.items.count) items" + (preview.freed.map { " · frees about \($0)" } ?? ""))
                .font(.caption.bold())
            previewList(preview.items.map { ($0.path, $0.detail) })
        }
        ForEach(preview.notes, id: \.self) { note in
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if !preview.isEmpty {
            Button {
                showCleanupConfirmation = true
            } label: {
                Label("Run Cleanup", systemImage: "trash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!maintenance.canRunCleanup)
        }
    }

    // MARK: - Autoremove

    @ViewBuilder
    private var autoremoveSection: some View {
        if maintenance.autoremovePreview != nil || !autoremoveOutput.isEmpty || maintenance.isRunningAutoremove {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Orphaned Packages Preview", systemImage: "leaf.arrow.circlepath")
                            .font(.subheadline.bold())
                        Spacer()
                        Button("Clear") {
                            maintenance.clearAutoremovePreview()
                            autoremoveOutput = ""
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(maintenance.isRunningAutoremove)
                    }

                    if let preview = maintenance.autoremovePreview {
                        if preview.isEmpty {
                            Label("No orphaned formulae.", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(preview.formulae.count) unneeded formulae")
                                .font(.caption.bold())
                            previewList(preview.formulae.map { ($0, nil) })
                            Button {
                                showAutoremoveConfirmation = true
                            } label: {
                                Label("Remove Orphans", systemImage: "leaf.arrow.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(!maintenance.canRunAutoremove)
                        }
                    } else {
                        runOutput(autoremoveOutput, isRunning: maintenance.isRunningAutoremove)
                    }
                }
            }
        }
    }

    // MARK: - Shared

    /// One row per path or formula, with its size or kind on the right.
    private func previewList(_ rows: [(name: String, detail: String?)]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if let detail = row.detail {
                            Text(detail)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }
        .frame(maxHeight: 200)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func runOutput(_ text: String, isRunning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Running…").font(.caption).foregroundStyle(.secondary)
                }
            }
            MutationOutputView(text: text)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: icon)
                        .font(.title2)
                        .frame(width: 28, height: 28)
                }
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(width: 80, height: 70)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
