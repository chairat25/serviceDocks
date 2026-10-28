import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Line splitter")
struct LineSplitterTests {
    @Test("emits complete lines and keeps the partial tail")
    func splitsLines() {
        let (next, lines) = LineSplitter().feeding(Data("one\ntwo\nthr".utf8))
        #expect(lines == ["one", "two"])

        let (_, rest) = next.feeding(Data("ee\n".utf8))
        #expect(rest == ["three"])
    }

    @Test("does not break a multi-byte character split across chunks")
    func keepsUTF8Intact() {
        let bytes = Array("สวัสดี\n".utf8)
        let (next, first) = LineSplitter().feeding(Data(bytes[0..<4]))
        let (_, second) = next.feeding(Data(bytes[4...]))
        #expect(first.isEmpty)
        #expect(second == ["สวัสดี"])
    }

    @Test("flushes the remaining tail on EOF")
    func flushes() {
        let (next, _) = LineSplitter().feeding(Data("tail".utf8))
        #expect(next.flushed() == ["tail"])
        #expect(LineSplitter().flushed().isEmpty)
    }

    @Test("handles CRLF line endings")
    func crlf() {
        let (_, lines) = LineSplitter().feeding(Data("a\r\nb\r\n".utf8))
        #expect(lines == ["a", "b"])
    }
}

@Suite("Log classification")
struct LogClassifierTests {
    @Test("strips ANSI colour codes")
    func stripsANSI() {
        #expect(LogClassifier.clean("\u{1B}[32m[Nest]\u{1B}[39m ok\u{1B}[0m") == "[Nest] ok")
    }

    @Test("keeps only the text after the last carriage return (progress bars)")
    func carriageReturn() {
        #expect(LogClassifier.clean("10%\r50%\rdone") == "done")
    }

    @Test("detects the level", arguments: [
        ("[Nest] 1  - ERROR [ExceptionHandler] boom", LogLevel.error),
        ("Error: connect ECONNREFUSED 127.0.0.1:5432", .error),
        ("npm ERR! code ELIFECYCLE", .error),
        ("UnhandledPromiseRejection: fatal", .error),
        ("[WARN] Token will expire in 5 minutes", .warn),
        ("(node:123) Warning: deprecated", .warn),
        ("[DEBUG] payload", .debug),
        ("POST /auth/login 200 432ms", .info),
        ("0 errors found", .info)
    ])
    func levels(line: String, level: LogLevel) {
        #expect(LogClassifier.level(of: line) == level)
    }
}

@Suite("Log buffer")
struct LogBufferTests {
    func line(_ text: String, _ level: LogLevel = .info) -> LogLine {
        LogLine(id: 0, serviceID: UUID(), date: Date(), text: text, level: level)
    }

    @Test("drops the oldest lines past capacity")
    func capacity() {
        var buffer = LogBuffer(capacity: 3)
        buffer.append(["a", "b", "c", "d", "e"].map { line($0) })
        #expect(buffer.lines.map(\.text) == ["c", "d", "e"])
    }

    @Test("counts errors and warnings since the last clear")
    func counts() {
        var buffer = LogBuffer(capacity: 2)
        buffer.append([line("x", .error), line("y", .warn), line("z", .error)])
        #expect(buffer.errorCount == 2)
        #expect(buffer.warnCount == 1)

        buffer.clear()
        #expect(buffer.lines.isEmpty)
        #expect(buffer.errorCount == 0)
    }
}

@Suite("Readiness")
struct ReadinessTests {
    @Test("recognises common dev-server ready lines", arguments: [
        "Server running on http://localhost:3001",
        "[Nest] 4120  - LOG [NestApplication] Nest application successfully started",
        "  VITE v5.4.0  ready in 312 ms",
        "✓ Compiled successfully in 1.2s",
        "Listening on port 8080",
        "  ➜  Local:   http://localhost:5173/",
        "webpack compiled successfully"
    ])
    func ready(line: String) {
        #expect(Readiness.isReady(line, customPattern: nil))
    }

    @Test("ignores ordinary lines")
    func notReady() {
        #expect(!Readiness.isReady("Compiling TypeScript...", customPattern: nil))
        #expect(!Readiness.isReady("Starting development server...", customPattern: nil))
    }

    @Test("uses a custom pattern when given")
    func custom() {
        #expect(Readiness.isReady("worker booted", customPattern: "booted"))
        #expect(!Readiness.isReady("worker booted", customPattern: "^ready$"))
    }

    @Test("an invalid custom pattern falls back to the defaults")
    func invalidCustom() {
        #expect(Readiness.isReady("Listening on port 1", customPattern: "(("))
    }
}

@Suite("Line clamping")
struct LineClampTests {
    @Test("leaves short lines alone")
    func short() {
        #expect(LogClassifier.clamp("hello", limit: 10) == "hello")
    }

    @Test("cuts very long lines and marks them")
    func long() {
        let clamped = LogClassifier.clamp(String(repeating: "x", count: 50), limit: 10)
        #expect(clamped == String(repeating: "x", count: 10) + "… (+40 chars)")
    }
}

@Suite("Log level scanner edge cases")
struct LevelScannerTests {
    @Test("keywords inside longer words do not count", arguments: [
        "errorless run", "terror in the night", "warned about nothing", "tracer started", "debugger attached"
    ])
    func substrings(line: String) {
        #expect(LogClassifier.level(of: line) == .info)
    }

    @Test("error beats warn beats debug wherever it appears")
    func priority() {
        #expect(LogClassifier.level(of: "debug warn ERROR") == .error)
        #expect(LogClassifier.level(of: "trace then Warning") == .warn)
        #expect(LogClassifier.level(of: "[VERBOSE] ok") == .debug)
    }

    @Test("works with Thai text and punctuation around keywords")
    func unicode() {
        #expect(LogClassifier.level(of: "สวัสดี [ERROR]: เชื่อมต่อไม่ได้") == .error)
        #expect(LogClassifier.level(of: "สวัสดีชาวโลก") == .info)
        #expect(LogClassifier.level(of: "(warn)") == .warn)
    }

    @Test("very long tokens and empty lines are safe")
    func extremes() {
        #expect(LogClassifier.level(of: String(repeating: "e", count: 5000)) == .info)
        #expect(LogClassifier.level(of: "Unhandled" + String(repeating: "x", count: 200)) == .error)
        #expect(LogClassifier.level(of: "") == .info)
    }

    @Test("hasContent ignores spaces and tabs only")
    func content() {
        #expect(!LogClassifier.hasContent("  \t "))
        #expect(LogClassifier.hasContent("  x "))
    }
}

@Suite("Ready matcher")
struct ReadyMatcherTests {
    @Test("a matcher can be reused across lines")
    func reuse() {
        let matcher = ReadyMatcher(customPattern: "booted \\d+")
        #expect(matcher.isReady("worker booted 3"))
        #expect(!matcher.isReady("worker booting"))
    }

    @Test("built-in detection is case-insensitive")
    func caseInsensitive() {
        let matcher = ReadyMatcher(customPattern: nil)
        #expect(matcher.isReady("SERVER RUNNING ON HTTP://LOCALHOST:3000"))
        #expect(matcher.isReady("COMPILED SUCCESSFULLY in 12ms"))
        #expect(!matcher.isReady("GET /api/v1/items 200 12ms"))
    }
}

@Suite("NestJS log levels")
struct NestLevelTests {
    @Test("uses the Nest level column, not words in the message", arguments: [
        ("[Nest] 1  - 10/28/2026, 11:34:56 AM   DEBUG [Bootstrap] Active log levels: verbose, debug, log, warn, error, fatal", LogLevel.debug),
        ("[Nest] 1  - 10/28/2026, 11:34:56 AM     LOG [Users] error count reset", .info),
        ("[Nest] 1  - 10/28/2026, 11:34:56 AM VERBOSE [Bootstrap] ok", .debug),
        ("[Nest] 1  - 10/28/2026, 11:34:56 AM    WARN [Bootstrap] slow", .warn),
        ("[Nest] 1  - 10/28/2026, 11:34:57 AM   ERROR [UnhandledRejection] Reason:", .error),
        ("[Nest] 1  - 10/28/2026, 11:34:57 AM   FATAL [Main] boom", .error)
    ])
    func nestLevels(line: String, level: LogLevel) {
        #expect(LogClassifier.level(of: line) == level)
    }
}

@Suite("Ready detection extras")
struct ReadyExtraTests {
    @Test("a Swagger URL line counts as ready")
    func swagger() {
        #expect(Readiness.isReady("[Nest] 1 - LOG [Bootstrap] Swagger documentation available at: http://localhost:3801/api-docs", customPattern: nil))
    }
}
