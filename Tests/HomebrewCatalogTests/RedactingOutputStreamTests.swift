import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("RedactingOutputStream")
struct RedactingOutputStreamTests {
    /// Collects what the stream hands to its sink.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var parts: [String] = []
        var text: String { lock.withLock { parts.joined() } }
        var count: Int { lock.withLock { parts.count } }
        func append(_ part: String) { lock.withLock { parts.append(part) } }
    }

    @Test("A token split across two reads is still redacted")
    func splitTokenIsRedacted() {
        let sink = Sink()
        let stream = RedactingOutputStream(sink: sink.append)
        stream.write("==> Cloning https://user:ghp_sec")
        stream.write("ret123@github.com/owner/tap.git\nDone\n")
        stream.finish()
        #expect(!sink.text.contains("ghp_secret123"))
        #expect(sink.text.contains(OutputRedactor.placeholder))
        #expect(sink.text.hasSuffix("Done\n"))
    }

    @Test("Nothing is emitted until a line completes; finish flushes the tail")
    func buffersUntilLineBreak() {
        let sink = Sink()
        let stream = RedactingOutputStream(sink: sink.append)
        stream.write("partial")
        #expect(sink.count == 0)
        stream.write(" line\rprogress 50%")
        #expect(sink.text == "partial line\r")
        stream.finish()
        #expect(sink.text == "partial line\rprogress 50%")
    }
}
