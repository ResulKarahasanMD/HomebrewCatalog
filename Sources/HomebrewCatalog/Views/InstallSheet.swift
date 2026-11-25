import SwiftUI
import SwiftData

struct PackageActionSheet: View {
    let item: any BrewItem
    let actionType: ActionType

    @Environment(BrewStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var output: String = ""
    @State private var isRunning: Bool = false
    @State private var isCancelling: Bool = false
    /// The run in flight; cancelling it stops this sheet's brew command and nothing else.
    @State private var runTask: Task<Void, Never>?
    /// The finished run; nil until the first run ends.
    @State private var result: ActionRecord?

    enum ActionType: String {
        case install = "Install"
        case uninstall = "Uninstall"
        case upgrade = "Upgrade"
        case reinstall = "Reinstall"

        var icon: String {
            switch self {
            case .install: return "arrow.down.circle.fill"
            case .uninstall: return "trash.fill"
            case .upgrade: return "arrow.up.circle.fill"
            case .reinstall: return "arrow.clockwise.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .install: return .blue
            case .uninstall: return .red
            case .upgrade: return .orange
            case .reinstall: return .purple
            }
        }

        func op(for item: any BrewItem) -> BrewMutation.Op {
            let name = item.brewIdentifier
            let isCask = item.itemType == .cask
            switch self {
            case .install: return .install(name: name, isCask: isCask)
            case .uninstall: return .uninstall(name: name, isCask: isCask)
            case .upgrade: return .upgrade(target: .named(name: name, isCask: isCask))
            case .reinstall: return .reinstall(name: name, isCask: isCask)
            }
        }
    }

    private var command: String {
        (["brew"] + actionType.op(for: item).brewArguments).joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: actionType.icon)
                    .font(.title)
                    .foregroundStyle(actionType.color)

                VStack(alignment: .leading) {
                    Text("\(actionType.rawValue) \(item.name)")
                        .font(.headline)
                    Text(item.desc ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Command
            HStack {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.quaternary)

            // Output
            if isRunning || result != nil {
                MutationOutputView(text: output)
            }

            Divider()

            if let result {
                MutationResultBanner(
                    title: resultTitle(result.status),
                    status: result.status,
                    detail: MutationSummary.detail(for: result),
                    output: output
                )
            }

            // Buttons
            HStack {
                if isRunning {
                    Button(isCancelling ? "Cancelling…" : "Cancel") {
                        isCancelling = true
                        runTask?.cancel()
                    }
                    .keyboardShortcut(.escape, localization: .custom)
                    .disabled(isCancelling)

                    Spacer()

                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running…")
                            .foregroundStyle(.secondary)
                    }
                } else if let result {
                    Spacer()

                    if result.status != .success, let retry = result.retryMutation {
                        Button("Retry") {
                            execute(retry)
                        }
                    }

                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.return, modifiers: [], localization: .custom)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape, localization: .custom)

                    Spacer()

                    Button(actionType.rawValue) {
                        execute(BrewMutation(actionType.op(for: item)))
                    }
                    .keyboardShortcut(.return, modifiers: .command, localization: .custom)
                    .buttonStyle(.borderedProminent)
                    .tint(actionType.color)
                }
            }
            .padding()
        }
        .interactiveDismissDisabled(isRunning)
        .frame(width: 520)
    }

    private func resultTitle(_ status: ActionStatus) -> String {
        switch status {
        case .success: "\(actionType.rawValue) completed successfully"
        case .cancelled: "\(actionType.rawValue) cancelled"
        default: "\(actionType.rawValue) failed"
        }
    }

    private func execute(_ mutation: BrewMutation) {
        isRunning = true
        isCancelling = false
        result = nil
        output = ""

        runTask = Task {
            let record = await store.mutations.run(mutation, context: modelContext) { output += $0 }
            output = MutationSummary.finalOutput(streamed: output, record: record)
            result = record
            isRunning = false
        }
    }
}
