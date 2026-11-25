import Testing
@testable import HomebrewCatalog

@Suite("StreamingOrder")
struct StreamingOrderTests {
    @Test("1000 ordered chunks round-trip through collector without reordering")
    func streamingPreservesOrder() async {
        let collector = OutputCollector()
        let (stream, continuation) = AsyncStream<(String, OutputCollector.Stream)>.makeStream()

        let drainTask = Task {
            for await (chunk, kind) in stream {
                await collector.append(chunk, to: kind)
            }
        }

        for i in 0..<1000 {
            continuation.yield(("\(i)\n", .stdout))
        }
        continuation.finish()
        _ = await drainTask.value

        let expected = (0..<1000).map { "\($0)\n" }.joined()
        let snap = await collector.snapshot()
        #expect(snap.stdout == expected)
        #expect(snap.stderr == "")
    }

    @Test("stdout and stderr are kept in independent buffers")
    func streamsAreIndependent() async {
        let collector = OutputCollector()
        let (stream, continuation) = AsyncStream<(String, OutputCollector.Stream)>.makeStream()

        let drainTask = Task {
            for await (chunk, kind) in stream {
                await collector.append(chunk, to: kind)
            }
        }

        continuation.yield(("alpha", .stdout))
        continuation.yield(("beta", .stderr))
        continuation.yield(("gamma", .stdout))
        continuation.finish()
        _ = await drainTask.value

        let snap = await collector.snapshot()
        #expect(snap.stdout == "alphagamma")
        #expect(snap.stderr == "beta")
    }
}
