import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Process stats")
struct ProcessStatsTests {
    @Test("sums CPU and memory per process group")
    func aggregates() {
        let output = """
          501   1.5  10240
          501   3.0  20480
          777   0.0   1024
        garbage line
        """
        let stats = ProcessStats.parse(output)
        #expect(stats[501] == ProcessStats.Sample(cpu: 4.5, memoryKB: 30720))
        #expect(stats[777] == ProcessStats.Sample(cpu: 0, memoryKB: 1024))
        #expect(stats.count == 2)
    }

    @Test("formats memory for humans")
    func memory() {
        #expect(ProcessStats.formatMemory(kb: 512) == "512 KB")
        #expect(ProcessStats.formatMemory(kb: 30720) == "30 MB")
        #expect(ProcessStats.formatMemory(kb: 2_097_152) == "2.0 GB")
    }

    @Test("keeps a bounded history")
    func history() {
        let history = ProcessStats.appending(5, to: [1, 2, 3], limit: 3)
        #expect(history == [2, 3, 5])
    }
}

@Suite("Env watch")
struct EnvWatchTests {
    let t0 = Date(timeIntervalSince1970: 100)
    let t1 = Date(timeIntervalSince1970: 200)

    @Test("only .env files count, examples are ignored", arguments: [
        (".env", true), (".env.local", true), (".env.development", true),
        (".env.example", false), (".env.sample", false), (".env.template", false),
        ("env.ts", false), (".envrc", false)
    ])
    func envFiles(name: String, expected: Bool) {
        #expect(EnvWatch.isEnvFile(name) == expected)
    }

    @Test("reports modified, added and removed files")
    func diff() {
        let before = [".env": t0, ".env.local": t0, ".env.test": t0]
        let after = [".env": t1, ".env.local": t0, ".env.dev": t1]
        #expect(EnvWatch.changedFiles(from: before, to: after) == [".env", ".env.dev", ".env.test"])
    }

    @Test("no change means no files")
    func noChange() {
        #expect(EnvWatch.changedFiles(from: [".env": t0], to: [".env": t0]).isEmpty)
    }
}
