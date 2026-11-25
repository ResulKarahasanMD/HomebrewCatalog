import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("BrewProcessIO")
struct BrewProcessIOTests {
    @Test("runProcess drains stdout larger than the pipe buffer")
    func largeStdoutCompletes() async throws {
        let python = "/usr/bin/python3"
        guard FileManager.default.isExecutableFile(atPath: python) else { return }

        let service = BrewProcessService.shared
        let result = try await service.runExecutableForTests(
            executable: python,
            arguments: ["-c", "import sys; sys.stdout.write('x' * 200_000)"],
            timeout: 15
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 200_000)
    }

    @Test("A process killed by its timeout reports timeout")
    func timeoutIsReportedAsTimeout() async {
        do {
            _ = try await BrewProcessService.shared.runExecutableForTests(
                executable: "/bin/sleep", arguments: ["5"], timeout: 0.3)
            Issue.record("expected a timeout")
        } catch BrewProcessError.timeout {
        } catch {
            Issue.record("expected timeout, got \(error)")
        }
    }

    // The termination callback's Task never saw the caller's cancellation, so a
    // cancelled command used to come back as a timeout.
    @Test("Cancelling the calling task reports cancelled, not timeout")
    func cancellationIsReportedAsCancelled() async throws {
        let task = Task {
            try await BrewProcessService.shared.runExecutableForTests(
                executable: "/bin/sleep", arguments: ["5"], timeout: 30)
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch BrewProcessError.cancelled {
        } catch {
            Issue.record("expected cancelled, got \(error)")
        }
    }

    // Each pipe read used to be decoded on its own, so a read ending inside a multi-byte
    // character failed to decode and was dropped whole, along with the read after it.
    @Test("A character split across two pipe reads is kept")
    func characterSplitAcrossReads() async throws {
        let result = try await BrewProcessService.shared.runExecutableForTests(
            executable: "/usr/bin/perl",
            arguments: ["-e", #"$|=1; print "before \xc4"; select(undef,undef,undef,0.2); print "\x9f after\n";"#],
            timeout: 15)

        #expect(result.stdout == "before \u{011F} after\n")
    }

    @Test("Large output of multi-byte characters at odd offsets is kept whole")
    func multiByteOutputAtOddOffsets() async throws {
        let result = try await BrewProcessService.shared.runExecutableForTests(
            executable: "/usr/bin/perl",
            arguments: ["-e", #"print "a" . ("\xc4\x9f" x 300000);"#],
            timeout: 15)

        #expect(result.stdout.count == 300_001)
        #expect(result.stdout.utf8.count == 600_001)
    }

    @Test("Cancelling one command's task leaves another command running")
    func cancellationIsScopedToItsTask() async throws {
        let service = BrewProcessService()
        let cancelled = Task {
            try await service.runExecutableForTests(executable: "/bin/sleep", arguments: ["5"], timeout: 30)
        }
        let other = Task {
            try await service.runExecutableForTests(executable: "/bin/sleep", arguments: ["1"], timeout: 30)
        }
        try await Task.sleep(for: .milliseconds(300))
        cancelled.cancel()

        await #expect(throws: BrewProcessError.self) { try await cancelled.value }
        #expect(try await other.value.exitCode == 0)
    }
}

@Suite("UTF8ChunkDecoder")
struct UTF8ChunkDecoderTests {
    /// "ğ" (2 bytes), "€" (3) and "🍺" (4), each cut after every possible byte.
    @Test("an unfinished sequence waits for the bytes that complete it", arguments: [
        ("ğ", 1), ("€", 1), ("€", 2), ("🍺", 1), ("🍺", 2), ("🍺", 3),
    ])
    func holdsUnfinishedSequence(character: String, cut: Int) {
        let bytes = Array(character.utf8)
        let decoder = UTF8ChunkDecoder()

        #expect(decoder.decode(Data([0x61] + bytes.prefix(cut))) == "a")
        #expect(decoder.decode(Data(bytes.dropFirst(cut) + [0x62])) == character + "b")
    }

    @Test("bytes still waiting at the end are decoded, not dropped")
    func finishFlushesRemainder() {
        let decoder = UTF8ChunkDecoder()
        #expect(decoder.decode(Data([0x61, 0xC4])) == "a")
        #expect(decoder.finish() == "\u{FFFD}")
        #expect(decoder.finish() == "")
    }

    @Test("invalid bytes become replacement characters instead of dropping the read")
    func invalidBytesAreReplaced() {
        let decoder = UTF8ChunkDecoder()
        #expect(decoder.decode(Data([0x61, 0xFF, 0x62, 0x0A])) == "a\u{FFFD}b\n")
    }
}
