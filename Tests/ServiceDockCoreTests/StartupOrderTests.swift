import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Start plan")
struct StartPlanTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test("groups services by stage, lowest stage first, keeping list order inside a stage")
    func groupsByStage() {
        let stages = StartPlan.stages([(a, 2), (b, 1), (c, 2), (d, 1)])
        #expect(stages == [[b, d], [a, c]])
    }

    @Test("a single stage yields one group")
    func singleStage() {
        #expect(StartPlan.stages([(a, 1), (b, 1)]) == [[a, b]])
    }

    @Test("gaps in stage numbers do not create empty groups")
    func gaps() {
        #expect(StartPlan.stages([(a, 5), (b, 1)]) == [[b], [a]])
    }

    @Test("no services yields no stages")
    func empty() {
        #expect(StartPlan.stages([]).isEmpty)
    }

    @Test("clamps stages to the allowed range")
    func clamp() {
        #expect(StartPlan.clamped(0) == StartPlan.stageRange.lowerBound)
        #expect(StartPlan.clamped(999) == StartPlan.stageRange.upperBound)
        #expect(StartPlan.clamped(3) == 3)
    }
}

@Suite("Stage gate")
struct StageGateTests {
    let a = UUID(), b = UUID()

    @Test("waits while any service is still pending")
    func waiting() {
        let outcome = StageGate.evaluate(signals: [a: .ready, b: .pending], elapsed: 5, timeout: 90)
        #expect(outcome == .waiting)
    }

    @Test("is ready once every service is ready")
    func ready() {
        #expect(StageGate.evaluate(signals: [a: .ready, b: .ready], elapsed: 5, timeout: 90) == .ready)
    }

    @Test("an empty stage is ready")
    func emptyReady() {
        #expect(StageGate.evaluate(signals: [:], elapsed: 0, timeout: 90) == .ready)
    }

    @Test("a failed service aborts even if others are pending or time ran out")
    func failed() {
        let outcome = StageGate.evaluate(signals: [a: .failed, b: .pending], elapsed: 999, timeout: 90)
        #expect(outcome == .failed([a]))
    }

    @Test("reports the pending services when the timeout passes")
    func timedOut() {
        let outcome = StageGate.evaluate(signals: [a: .ready, b: .pending], elapsed: 90, timeout: 90)
        #expect(outcome == .timedOut([b]))
    }

    @Test("ready wins over the timeout when everything is ready")
    func readyBeatsTimeout() {
        #expect(StageGate.evaluate(signals: [a: .ready], elapsed: 500, timeout: 90) == .ready)
    }
}

@Suite("Startup config persistence")
struct StartupConfigTests {
    @Test("old config files without startStage load with stage 1 and the default timeout")
    func legacyJSON() throws {
        let json = """
        {"services":[{"id":"6F1C2B3A-0000-4000-8000-000000000001","name":"auth","path":"/a",
        "command":"yarn dev","icon":"server.rack"}]}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.services.first?.startStage == 1)
        #expect(config.stageTimeoutSeconds == AppConfig.defaultStageTimeout)
    }

    @Test("stage and timeout round-trip")
    func roundTrip() throws {
        let service = ServiceConfig(name: "auth", path: "/a", command: "x", startStage: 3)
        let config = AppConfig(services: [service], stageTimeoutSeconds: 45)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }
}

@Suite("Startup mode")
struct StartupModeTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test("parallel mode puts every service in one stage, in list order")
    func parallel() {
        #expect(StartPlan.stages([(a, 2), (b, 1), (c, 3)], mode: .parallel) == [[a, b, c]])
    }

    @Test("parallel mode with no services yields no stages")
    func parallelEmpty() {
        #expect(StartPlan.stages([], mode: .parallel).isEmpty)
    }

    @Test("staged is the default mode")
    func stagedDefault() {
        #expect(StartPlan.stages([(a, 2), (b, 1)]) == StartPlan.stages([(a, 2), (b, 1)], mode: .staged))
    }

    @Test("old config files load staged, with notifications on and auto-restart off")
    func legacyDefaults() throws {
        let json = """
        {"services":[{"id":"6F1C2B3A-0000-4000-8000-000000000001","name":"auth","path":"/a",
        "command":"yarn dev","icon":"server.rack"}]}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.startupMode == .staged)
        #expect(config.notifyOnCrash)
        #expect(config.services.first?.autoRestart == false)
    }

    @Test("startup mode, notify and auto-restart round-trip")
    func roundTrip() throws {
        let service = ServiceConfig(name: "auth", path: "/a", command: "x", autoRestart: true)
        let config = AppConfig(services: [service], startupMode: .parallel, notifyOnCrash: false)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }
}
