import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Service config")
struct ServiceConfigTests {
    let home = "/Users/dev"

    @Test("expands a leading tilde to the home directory")
    func expandsTilde() {
        let config = ServiceConfig(name: "auth", path: "~/projects/auth", command: "yarn start:dev")
        #expect(config.expandedPath(home: home) == "/Users/dev/projects/auth")
    }

    @Test("leaves absolute paths untouched")
    func keepsAbsolutePath() {
        let config = ServiceConfig(name: "auth", path: "/srv/auth", command: "yarn start:dev")
        #expect(config.expandedPath(home: home) == "/srv/auth")
    }

    @Test("abbreviates the home directory for display")
    func abbreviatesHome() {
        #expect(ServiceConfig.abbreviate("/Users/dev/projects/web", home: home) == "~/projects/web")
        #expect(ServiceConfig.abbreviate("/srv/web", home: home) == "/srv/web")
    }

    @Test("reports every missing field")
    func validatesEmptyFields() {
        let config = ServiceConfig(name: "  ", path: "", command: " ")
        let errors = config.validate(home: home, directoryExists: { _ in true })
        #expect(errors == [.emptyName, .emptyPath, .emptyCommand])
    }

    @Test("rejects a path that is not a directory")
    func validatesDirectory() {
        let config = ServiceConfig(name: "auth", path: "~/missing", command: "yarn dev")
        let errors = config.validate(home: home, directoryExists: { _ in false })
        #expect(errors == [.directoryNotFound("/Users/dev/missing")])
    }

    @Test("rejects a URL that is not http(s)")
    func validatesURL() {
        let bad = ServiceConfig(name: "a", path: "/a", command: "x", url: "localhost:3000")
        let good = ServiceConfig(name: "a", path: "/a", command: "x", url: "http://localhost:3000")
        #expect(bad.validate(home: home, directoryExists: { _ in true }) == [.invalidURL])
        #expect(good.validate(home: home, directoryExists: { _ in true }).isEmpty)
    }

    @Test("suggests an icon from the service name",
          arguments: [("auth-service", "shield.lefthalf.filled"),
                      ("web-frontend", "desktopcomputer"),
                      ("backend-gateway", "point.3.connected.trianglepath.dotted"),
                      ("worker", "gearshape.fill"),
                      ("master-data-service", "cylinder.split.1x2.fill"),
                      ("profile-service", "person.fill"),
                      ("something", "server.rack")])
    func suggestsIcon(name: String, icon: String) {
        #expect(ServiceConfig.suggestedIcon(for: name) == icon)
    }

    @Test("round-trips through the config store")
    func storeRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("services.json")
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = AppConfig(services: [ServiceConfig(name: "auth", path: "/a", command: "yarn dev",
                                                        url: "http://localhost:3001")])

        try ConfigStore.save(config, to: url)
        let loaded = try ConfigStore.load(from: url)

        #expect(loaded == config)
    }

    @Test("loads an empty config when the file does not exist")
    func storeMissingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        #expect(try ConfigStore.load(from: url) == AppConfig())
    }

    @Test("throws a readable error for a corrupt file")
    func storeCorruptFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{not json".utf8).write(to: url)
        #expect(throws: ConfigStoreError.self) { try ConfigStore.load(from: url) }
    }
}

@Suite("Shell command")
struct ShellCommandTests {
    @Test("runs the command inside the folder through a login shell")
    func buildsArguments() {
        let args = ShellCommand.arguments(shell: "/bin/zsh", directory: "/Users/dev/my app", command: "yarn start:dev")
        #expect(args == ["/bin/zsh", "-l", "-i", "-c", "cd '/Users/dev/my app' && yarn start:dev"])
    }

    @Test("escapes single quotes in the folder path")
    func quotesPath() {
        #expect(ShellCommand.quote("it's") == #"'it'\''s'"#)
    }
}

@Suite("Service status")
struct ServiceStatusTests {
    @Test("counts only live states as running")
    func liveness() {
        #expect(ServiceStatus.running.isAlive)
        #expect(ServiceStatus.starting.isAlive)
        #expect(ServiceStatus.stopping.isAlive)
        #expect(!ServiceStatus.stopped.isAlive)
        #expect(!ServiceStatus.down(exitCode: 1).isAlive)
    }

    @Test("labels a crash with its exit code")
    func labels() {
        #expect(ServiceStatus.down(exitCode: 1).label == "Down (exit 1)")
        #expect(ServiceStatus.down(exitCode: -9).label == "Down (signal 9)")
        #expect(ServiceStatus.running.label == "Running")
    }
}

@Suite("Duration format")
struct DurationFormatTests {
    @Test("formats uptime as hh:mm:ss", arguments: [(0.0, "00:00:00"), (754.9, "00:12:34"), (90_061, "25:01:01")])
    func formats(seconds: Double, text: String) {
        #expect(DurationFormat.clock(seconds) == text)
    }
}
