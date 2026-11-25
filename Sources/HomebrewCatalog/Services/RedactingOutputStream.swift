import Foundation

/// Passes streamed command output to `sink` redacted, one complete line at a time.
/// Buffering to a line boundary keeps a secret that is split across two pipe reads
/// whole for the redactor, and keeps its `^…$` patterns anchored to real line starts.
final class RedactingOutputStream: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private let redactor = OutputRedactor()
    private let sink: @Sendable (String) -> Void

    init(sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
    }

    func write(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        pending += chunk
        // `\r` counts as a boundary too, so progress bars keep updating.
        guard let cut = pending.lastIndex(where: \.isNewline) else { return }
        let complete = String(pending[...cut])
        pending = String(pending[pending.index(after: cut)...])
        // Called under the lock so concurrent writers can't reorder lines.
        sink(redactor.redact(complete))
    }

    /// Emits whatever followed the last line break; call once the command has finished.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return }
        let rest = pending
        pending = ""
        sink(redactor.redact(rest))
    }
}
