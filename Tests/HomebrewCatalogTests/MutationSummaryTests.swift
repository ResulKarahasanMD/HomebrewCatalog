import Testing
@testable import HomebrewCatalog

@Suite("MutationSummary")
struct MutationSummaryTests {
    static let sequences: [(statuses: [ActionStatus], planned: Int, title: String, overall: ActionStatus)] = [
        ([.success, .success, .success], 3, "3 of 3 upgraded", .success),
        ([.success, .failed, .success], 3, "2 of 3 upgraded · 1 failed", .failed),
        ([.failed, .failed], 2, "0 of 2 upgraded · 2 failed", .failed),
        ([.success, .cancelled], 3, "1 of 3 upgraded · cancelled, 1 skipped", .cancelled),
        ([.failed, .cancelled], 2, "0 of 2 upgraded · 1 failed · cancelled", .cancelled),
    ]

    @Test("a finished sequence is summarised by what upgraded, failed and was skipped", arguments: sequences)
    func sequenceSummary(statuses: [ActionStatus], planned: Int, title: String, overall: ActionStatus) {
        let summary = MutationSummary.sequence(statuses: statuses, planned: planned)

        #expect(summary.title == title)
        #expect(summary.status == overall)
    }

    private func record(
        _ status: ActionStatus, exitCode: Int32, output: String = "", errorOutput: String = "", seconds: Double = 12
    ) -> ActionRecord {
        let record = ActionRecord(mutation: BrewMutation(.install(name: "jq", isCask: false)))
        record.status = status
        record.exitCode = exitCode
        record.output = output
        record.errorOutput = errorOutput
        record.completedAt = record.startedAt.addingTimeInterval(seconds)
        return record
    }

    @Test("streamed output is kept as is when brew exited on its own")
    func streamedOutputIsKept() {
        let failed = record(.failed, exitCode: 1, output: "", errorOutput: "Error: download failed")

        let text = MutationSummary.finalOutput(streamed: "==> Fetching jq\nError: download failed\n", record: failed)

        #expect(text == "==> Fetching jq\nError: download failed\n")
    }

    @Test("a command that streamed nothing shows the recorded stdout and stderr")
    func unstreamedOutputFallsBackToRecord() {
        let failedPin = record(.failed, exitCode: 1, output: "", errorOutput: "Error: No such keg: /opt/homebrew/Cellar/jq")

        #expect(MutationSummary.finalOutput(streamed: "", record: failedPin)
            == "Error: No such keg: /opt/homebrew/Cellar/jq")
    }

    @Test("when brew never exited, the reason is appended to the streamed output")
    func interruptedRunAppendsReason() {
        let cancelled = record(.cancelled, exitCode: -1, errorOutput: "Command was cancelled.")

        #expect(MutationSummary.finalOutput(streamed: "==> Downloading jq", record: cancelled)
            == "==> Downloading jq\nCommand was cancelled.")
    }

    @Test("the detail line gives the exit code only when brew produced one",
          arguments: [
              (ActionStatus.success, Int32(0), "Exit code 0 · 12s"),
              (.failed, 1, "Exit code 1 · 12s"),
              (.failed, -1, "Did not finish · 12s"),
              (.cancelled, -1, "Stopped after 12s"),
          ])
    func detailLine(status: ActionStatus, exitCode: Int32, detail: String) {
        #expect(MutationSummary.detail(for: record(status, exitCode: exitCode)) == detail)
    }
}
