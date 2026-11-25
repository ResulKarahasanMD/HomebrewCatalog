import Foundation

/// Redacts brew output and hands it to a main-actor sink in the order brew wrote it.
/// brew's pipes are read on background threads; a single consumer keeps the lines in
/// order, and `run` returns only after every line has reached the sink.
@MainActor
enum OrderedOutput {
    static func run<T>(
        sink: @escaping @MainActor (String) -> Void,
        _ body: (_ onOutput: @escaping @Sendable (String) -> Void) async throws -> T
    ) async rethrows -> T {
        let (lines, continuation) = AsyncStream<String>.makeStream()
        let drain = Task { @MainActor in
            for await line in lines {
                sink(line)
            }
        }
        let redacting = RedactingOutputStream { continuation.yield($0) }

        do {
            let value = try await body { redacting.write($0) }
            redacting.finish()
            continuation.finish()
            await drain.value
            return value
        } catch {
            redacting.finish()
            continuation.finish()
            await drain.value
            throw error
        }
    }
}
