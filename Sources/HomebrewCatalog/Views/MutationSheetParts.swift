import AppKit
import SwiftUI

/// Command output pinned to its latest line. The height is fixed so the sheet does not
/// grow while output streams in.
struct MutationOutputView: View {
    let text: String

    private static let bottomID = "output-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomID)
            }
            .frame(height: 250)
            .background(.background)
            .overlay {
                if text.isEmpty {
                    Text("Waiting for brew…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: text) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }
}

/// How a run ended, with a button that copies the whole output.
struct MutationResultBanner: View {
    let title: String
    let status: ActionStatus
    var detail: String?
    let output: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
            } label: {
                Label("Copy Output", systemImage: "doc.on.doc")
            }
            .disabled(output.isEmpty)
        }
        .padding()
        .background(tint.opacity(0.1))
    }

    private var symbol: String {
        switch status {
        case .success: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "slash.circle.fill"
        case .pending, .running: "clock"
        }
    }

    private var tint: Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .cancelled: .orange
        case .pending, .running: .secondary
        }
    }
}

enum MutationSummary {
    /// One line for a finished upgrade sequence, e.g. "1 of 3 upgraded · cancelled, 1 skipped".
    /// `statuses` has one entry per step that ran; steps after a cancel never ran.
    static func sequence(statuses: [ActionStatus], planned: Int) -> (title: String, status: ActionStatus) {
        let upgraded = statuses.filter { $0 == .success }.count
        let failed = statuses.filter { $0 == .failed }.count
        let cancelled = statuses.contains(.cancelled)
        let skipped = planned - statuses.count

        var parts = ["\(upgraded) of \(planned) upgraded"]
        if failed > 0 { parts.append("\(failed) failed") }
        if cancelled { parts.append(skipped > 0 ? "cancelled, \(skipped) skipped" : "cancelled") }

        let status: ActionStatus = cancelled ? .cancelled : (failed > 0 ? .failed : .success)
        return (parts.joined(separator: " · "), status)
    }

    /// Output to show once a run ends. Streamed output already holds brew's stdout and
    /// stderr; pin/unpin stream nothing, and when brew never exited (cancelled, not found)
    /// the reason exists only in the record.
    static func finalOutput(streamed: String, record: ActionRecord) -> String {
        if streamed.isEmpty {
            return [record.output, record.errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        guard record.exitCode == -1, !record.errorOutput.isEmpty else { return streamed }
        return streamed + (streamed.hasSuffix("\n") ? "" : "\n") + record.errorOutput
    }

    static func detail(for record: ActionRecord) -> String {
        if record.status == .cancelled { return "Stopped after \(record.formattedDuration)" }
        if record.exitCode == -1 { return "Did not finish · \(record.formattedDuration)" }
        return "Exit code \(record.exitCode) · \(record.formattedDuration)"
    }
}
