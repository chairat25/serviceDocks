import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Restart policy")
struct RestartPolicyTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("backs off 2s, 5s, 10s, then gives up")
    func sequence() {
        var policy = RestartPolicy()
        #expect(policy.crashed(at: t0) == .restart(after: .seconds(2), attempt: 1))
        #expect(policy.crashed(at: t0 + 3) == .restart(after: .seconds(5), attempt: 2))
        #expect(policy.crashed(at: t0 + 9) == .restart(after: .seconds(10), attempt: 3))
        #expect(policy.crashed(at: t0 + 20) == .giveUp)
    }

    @Test("running for 60 seconds starts the count over")
    func stableRunResets() {
        var policy = RestartPolicy()
        _ = policy.crashed(at: t0)
        _ = policy.crashed(at: t0 + 3)
        policy.becameRunning(at: t0 + 10)
        #expect(policy.crashed(at: t0 + 70) == .restart(after: .seconds(2), attempt: 1))
    }

    @Test("running for less than 60 seconds keeps counting")
    func shortRunKeepsCount() {
        var policy = RestartPolicy()
        _ = policy.crashed(at: t0)
        policy.becameRunning(at: t0 + 5)
        #expect(policy.crashed(at: t0 + 30) == .restart(after: .seconds(5), attempt: 2))
    }

    @Test("crashing before ever running keeps counting")
    func neverRan() {
        var policy = RestartPolicy()
        _ = policy.crashed(at: t0)
        #expect(policy.crashed(at: t0 + 500) == .restart(after: .seconds(5), attempt: 2))
    }

    @Test("reset starts over")
    func reset() {
        var policy = RestartPolicy()
        _ = policy.crashed(at: t0)
        _ = policy.crashed(at: t0 + 1)
        policy.reset()
        #expect(policy.attempts == 0)
        #expect(policy.crashed(at: t0 + 2) == .restart(after: .seconds(2), attempt: 1))
    }
}
