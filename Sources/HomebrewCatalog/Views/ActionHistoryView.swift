import SwiftUI
import SwiftData

struct ActionHistoryView: View {
    @Query(sort: \ActionRecord.startedAt, order: .reverse) private var records: [ActionRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(BrewStore.self) private var store

    @State private var expandedID: String?
    @State private var isRetrying: Bool = false
    /// Retry stages its mutation here; it runs only after the confirmation sheet.
    @State private var retryGate = RetryGate()

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("\(records.count) actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !records.isEmpty {
                    Button(role: .destructive) {
                        PersistenceController.shared.clearActionHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if records.isEmpty {
                EmptyStateView(
                    icon: "list.clipboard",
                    title: "No Action History",
                    message: "Actions like install, uninstall, and upgrade will appear here."
                )
            } else {
                List {
                    ForEach(records) { record in
                        actionRow(record)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Action History")
        .sheet(isPresented: retrySheetBinding) {
            retryConfirmationSheet
        }
    }

    private var retrySheetBinding: Binding<Bool> {
        Binding(
            get: { retryGate.pending != nil || retryGate.refusal != nil },
            set: { if !$0 { retryGate.cancel() } }
        )
    }

    /// Shows the exact command a Retry would run, as the install sheet does, before it runs.
    @ViewBuilder
    private var retryConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Run this command again?", systemImage: "arrow.clockwise.circle.fill")
                .font(.headline)

            if let command = retryGate.command {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            } else if let refusal = retryGate.refusal {
                Label(refusal, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel") { retryGate.cancel() }
                    .keyboardShortcut(.escape, localization: .custom)
                Spacer()
                if retryGate.pending != nil {
                    Button("Retry") { confirmRetry() }
                        .keyboardShortcut(.return, modifiers: .command, localization: .custom)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 480)
    }

    @ViewBuilder
    private func actionRow(_ record: ActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon(record.status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.displayCommand)
                        .font(.system(.body, design: .monospaced, weight: .medium))

                    HStack(spacing: 12) {
                        Text(record.startedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(record.formattedDuration)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if record.status == .failed || record.status == .cancelled, record.retryMutation != nil {
                    Button {
                        retryAction(record)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRetrying)
                }

                Button {
                    withAnimation {
                        expandedID = expandedID == record.id ? nil : record.id
                    }
                } label: {
                    Image(systemName: expandedID == record.id ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if expandedID == record.id {
                VStack(alignment: .leading, spacing: 4) {
                    if !record.output.isEmpty {
                        Text("Output:")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(record.output)
                                .font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 150)
                        .padding(6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    if !record.errorOutput.isEmpty {
                        Text("Error:")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                        Text(record.errorOutput)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(6)
                            .background(.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                    HStack {
                        Text("Exit code: \(record.exitCode)")
                        Spacer()
                        Text("Package: \(record.packageName)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusIcon(_ status: ActionStatus) -> some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .cancelled:
            Image(systemName: "slash.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func retryAction(_ record: ActionRecord) {
        retryGate.request(record.retryMutation)
    }

    private func confirmRetry() {
        guard let mutation = retryGate.confirm() else { return }
        isRetrying = true
        Task {
            await store.mutations.run(mutation, context: modelContext)
            isRetrying = false
        }
    }
}
