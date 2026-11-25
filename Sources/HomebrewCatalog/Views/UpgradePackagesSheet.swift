import SwiftData
import SwiftUI

/// Upgrades the checked packages one at a time with progress, or everything outdated in a
/// single `brew upgrade` when nothing is checked.
struct UpgradePackagesSheet: View {
    /// Outdated, non-pinned packages that `brew upgrade` with no arguments would touch.
    let upgradableCount: Int
    /// Called after each run with the names that did not upgrade.
    let onFinish: (Set<String>) -> Void

    @Environment(BrewStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Packages to upgrade in order; empty means everything. Retry narrows it.
    @State private var targets: [OutdatedInfo]
    @State private var output = ""
    @State private var isRunning = false
    @State private var isCancelling = false
    /// The run in flight; cancelling it stops this sheet's brew commands and nothing else.
    @State private var runTask: Task<Void, Never>?
    @State private var finished: Finished?

    private enum Finished {
        case all(ActionRecord)
        case sequence(statuses: [ActionStatus], planned: Int, notUpgraded: [OutdatedInfo])
    }

    init(plan: [OutdatedInfo], upgradableCount: Int, onFinish: @escaping (Set<String>) -> Void) {
        _targets = State(initialValue: plan)
        self.upgradableCount = upgradableCount
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isRunning {
                UpgradeProgressView(step: store.mutations.sequenceProgress)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
            }

            if isRunning || finished != nil {
                MutationOutputView(text: output)
            }

            Divider()

            if let finished {
                resultBanner(finished)
            }

            buttons
                .padding()
        }
        .frame(width: 520)
        .interactiveDismissDisabled(isRunning)
    }

    private var header: some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text(targets.isEmpty ? "Upgrade All Packages" : "Upgrade Selected Packages")
                    .font(.headline)
                Text(
                    targets.isEmpty
                        ? "\(upgradableCount) packages will be upgraded in one brew command"
                        : targets.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func resultBanner(_ finished: Finished) -> some View {
        switch finished {
        case .all(let record):
            MutationResultBanner(
                title: record.status == .success
                    ? "All outdated packages upgraded"
                    : (record.status == .cancelled ? "Upgrade cancelled" : "Upgrade failed"),
                status: record.status,
                detail: MutationSummary.detail(for: record),
                output: output
            )
        case .sequence(let statuses, let planned, _):
            let summary = MutationSummary.sequence(statuses: statuses, planned: planned)
            MutationResultBanner(title: summary.title, status: summary.status, output: output)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            if isRunning {
                Button(isCancelling ? "Cancelling…" : "Cancel") {
                    isCancelling = true
                    runTask?.cancel()
                }
                .keyboardShortcut(.escape, localization: .custom)
                .disabled(isCancelling)

                Spacer()

                ProgressView()
                    .controlSize(.small)
            } else if let finished {
                Spacer()

                if let retryTargets = retryTargets(after: finished) {
                    Button("Retry") {
                        targets = retryTargets
                        start()
                    }
                }

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [], localization: .custom)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape, localization: .custom)

                Spacer()

                Button(targets.isEmpty ? "Upgrade All" : "Upgrade \(targets.count)") {
                    start()
                }
                .keyboardShortcut(.return, modifiers: .command, localization: .custom)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }

    /// What Retry runs again, or nil when everything upgraded.
    private func retryTargets(after finished: Finished) -> [OutdatedInfo]? {
        switch finished {
        case .all(let record):
            return record.status == .success ? nil : []
        case .sequence(_, _, let notUpgraded):
            return notUpgraded.isEmpty ? nil : notUpgraded
        }
    }

    private func start() {
        isRunning = true
        isCancelling = false
        finished = nil
        output = ""
        let targets = targets

        runTask = Task {
            if targets.isEmpty {
                let record = await store.mutations.run(BrewMutation(.upgrade(target: .all)), context: modelContext) {
                    output += $0
                }
                output = MutationSummary.finalOutput(streamed: output, record: record)
                finished = .all(record)
                onFinish([])
            } else {
                let mutations = targets.map {
                    BrewMutation(.upgrade(target: .named(name: $0.name, isCask: $0.itemType == .cask)))
                }
                let records = await store.mutations.runSequence(mutations, context: modelContext) {
                    output += $0
                }
                if let last = records.last {
                    output = MutationSummary.finalOutput(streamed: output, record: last)
                }
                // Records line up with the first targets; a cancel leaves the rest unrun.
                let upgraded = Set(zip(targets, records).filter { $0.1.status == .success }.map(\.0.name))
                let notUpgraded = targets.filter { !upgraded.contains($0.name) }
                finished = .sequence(
                    statuses: records.map(\.status), planned: targets.count, notUpgraded: notUpgraded)
                onFinish(Set(notUpgraded.map(\.name)))
            }
            isRunning = false
        }
    }
}

/// "Upgrading wget, 2 of 3" for a sequence; an indeterminate bar for a single `brew upgrade`.
struct UpgradeProgressView: View {
    let step: MutationCoordinator.SequenceProgress?

    var body: some View {
        if let step {
            ProgressView(value: Double(step.completed), total: Double(step.total)) {
                Text("Upgrading \(step.current)")
                    .font(.subheadline)
            } currentValueLabel: {
                Text("\(step.completed + 1) of \(step.total)")
            }
        } else {
            ProgressView {
                Text("Upgrading all outdated packages")
                    .font(.subheadline)
            }
            .progressViewStyle(.linear)
        }
    }
}
