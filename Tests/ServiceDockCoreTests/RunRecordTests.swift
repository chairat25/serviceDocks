import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Stale process detection")
struct RunRecordTests {
    let record = RunRecord(pgid: 4242, startTime: "Wed Oct 28 10:31:02 2026", name: "report")

    @Test("the same process is recognised by its start time")
    func sameProcess() {
        #expect(StaleProcess.isSame(record, currentStartTime: "Wed Oct 28 10:31:02 2026"))
    }

    @Test("a reused pid with a different start time is left alone")
    func reusedPID() {
        #expect(!StaleProcess.isSame(record, currentStartTime: "Wed Oct 28 11:15:40 2026"))
    }

    @Test("a process that is gone is not killed")
    func gone() {
        #expect(!StaleProcess.isSame(record, currentStartTime: nil))
    }

    @Test("records round-trip through JSON")
    func roundTrip() throws {
        let data = try JSONEncoder().encode([record])
        #expect(try JSONDecoder().decode([RunRecord].self, from: data) == [record])
    }

    @Test("parses ps output, trimming whitespace and empty output")
    func parsesPS() {
        #expect(StaleProcess.startTime(fromPS: "Wed Oct 28 10:31:02 2026\n") == "Wed Oct 28 10:31:02 2026")
        #expect(StaleProcess.startTime(fromPS: "  \n") == nil)
    }
}
