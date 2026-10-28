import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Port list")
struct PortListTests {
    @Test("parses comma/space separated ports, dropping junk and duplicates", arguments: [
        ("8000, 50055", [8000, 50055]),
        ("8000 8000  3001", [8000, 3001]),
        ("abc, 70000, 0, 443", [443]),
        ("", [])
    ])
    func parse(text: String, expected: [Int]) {
        #expect(PortList.parse(text) == expected)
    }

    @Test("formats ports for the editor field")
    func format() {
        #expect(PortList.format([8000, 50055]) == "8000, 50055")
    }
}

@Suite("lsof parsing")
struct LsofParserTests {
    @Test("extracts listening ports from -Fn output (IPv4, wildcard, IPv6)")
    func listeningPorts() {
        let output = "p123\nn*:8000\nn127.0.0.1:3001\nn[::1]:50055\nn*:8000\nf5\n"
        #expect(LsofParser.listeningPorts(fromFn: output) == [3001, 8000, 50055])
    }

    @Test("ignores lines that are not addresses")
    func ignoresNoise() {
        #expect(LsofParser.listeningPorts(fromFn: "p1\ncnode\nnlocalhost\n").isEmpty)
    }

    @Test("maps each pid to the wanted ports it listens on (-Fpn output)")
    func portsByPid() {
        let output = "p98238\nn*:8000\nn*:50055\nn*:9999\np656\nn*:8000\n"
        let result = LsofParser.portsByPid(fromFpn: output, wanted: [8000, 50055])
        #expect(result == [98238: [8000, 50055], 656: [8000]])
    }

    @Test("a pid with none of the wanted ports is left out")
    func unwantedPorts() {
        #expect(LsofParser.portsByPid(fromFpn: "p1\nn*:1234\n", wanted: [8000]).isEmpty)
    }
}

@Suite("Ports to free")
struct PortsToFreeTests {
    @Test("combines manual, learned and URL ports")
    func combined() {
        var config = ServiceConfig(name: "report", path: "/a", command: "x", url: "http://localhost:8000")
        config.ports = [50055]
        config.learnedPorts = [8000, 9229]
        #expect(config.portsToFree == [8000, 9229, 50055])
    }

    @Test("a URL without an explicit port adds nothing")
    func urlWithoutPort() {
        let config = ServiceConfig(name: "a", path: "/a", command: "x", url: "https://example.com")
        #expect(config.portsToFree.isEmpty)
    }

    @Test("nothing is freed when the option is off")
    func disabled() {
        var config = ServiceConfig(name: "a", path: "/a", command: "x", url: "http://localhost:3001")
        config.freesPortsOnStart = false
        #expect(config.portsToFree.isEmpty)
    }

    @Test("old config files default to freeing ports")
    func legacyDefault() throws {
        let json = #"{"id":"6F1C2B3A-0000-4000-8000-000000000001","name":"a","path":"/a","command":"x","icon":"server.rack"}"#
        let config = try JSONDecoder().decode(ServiceConfig.self, from: Data(json.utf8))
        #expect(config.freesPortsOnStart)
        #expect(config.ports.isEmpty)
        #expect(config.learnedPorts.isEmpty)
    }

    @Test("merging learned ports keeps a bounded sorted set")
    func merge() {
        #expect(PortList.merge([8000], with: [3001, 8000], limit: 3) == [3001, 8000])
        #expect(PortList.merge([1, 2, 3], with: [4], limit: 3) == [1, 2, 3])
    }
}
