import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Config transfer")
struct ConfigTransferTests {
    let home = "/Users/dev"

    func service(_ name: String, _ path: String, command: String = "yarn dev") -> ServiceConfig {
        ServiceConfig(name: name, path: path, command: command)
    }

    // MARK: common root

    @Test("common root is the shared parent folder")
    func root() {
        let paths = ["~/p/genie/auth", "~/p/genie/profile", "~/p/genie/genie-fe"]
        #expect(ConfigTransfer.commonRoot(of: paths) == "~/p/genie")
    }

    @Test("common root of a single path is its parent")
    func rootOfOne() {
        #expect(ConfigTransfer.commonRoot(of: ["~/p/genie/auth"]) == "~/p/genie")
    }

    @Test("common root compares whole folder names")
    func rootWholeComponents() {
        #expect(ConfigTransfer.commonRoot(of: ["~/p/app", "~/p/apple"]) == "~/p")
    }

    @Test("trailing slashes are ignored")
    func rootTrailingSlash() {
        #expect(ConfigTransfer.commonRoot(of: ["~/p/a/", "~/p/b"]) == "~/p")
    }

    @Test("no shared folder, or no paths, yields nil")
    func noRoot() {
        #expect(ConfigTransfer.commonRoot(of: ["/srv/a", "/opt/b"]) == nil)
        #expect(ConfigTransfer.commonRoot(of: []) == nil)
    }

    // MARK: remap

    @Test("remap moves a path under the new root and abbreviates home")
    func remap() {
        let moved = ConfigTransfer.remap("~/p/genie/auth", from: "~/p/genie", to: "/Users/dev/work/genie/", home: home)
        #expect(moved == "~/work/genie/auth")
    }

    @Test("remap of the root itself is the new root")
    func remapRoot() {
        #expect(ConfigTransfer.remap("~/p/genie", from: "~/p/genie", to: "/srv/genie", home: home) == "/srv/genie")
    }

    @Test("remap leaves paths outside the old root alone")
    func remapOutside() {
        #expect(ConfigTransfer.remap("~/p/genieX/auth", from: "~/p/genie", to: "/x", home: home) == "~/p/genieX/auth")
    }

    @Test("remapping a config moves every service")
    func remapConfig() {
        let config = AppConfig(services: [service("auth", "~/p/genie/auth"), service("fe", "~/p/genie/fe")])
        let moved = ConfigTransfer.remapping(config, from: "~/p/genie", to: "/Users/dev/code/genie", home: home)
        #expect(moved.services.map(\.path) == ["~/code/genie/auth", "~/code/genie/fe"])
    }

    // MARK: portable

    @Test("portable writes paths under home as ~ and leaves others alone")
    func portable() {
        let config = AppConfig(services: [service("a", "/Users/dev/p/a"), service("b", "/srv/b"), service("c", "~/c")])
        let result = ConfigTransfer.portable(config, home: home)
        #expect(result.services.map(\.path) == ["~/p/a", "/srv/b", "~/c"])
    }

    // MARK: merge

    @Test("merge updates a same-name service and keeps its local id")
    func mergeUpdates() {
        let local = service("Auth", "~/old", command: "old")
        let incoming = service(" auth ", "~/new", command: "new")
        let merged = ConfigTransfer.merge(local: AppConfig(services: [local]), imported: AppConfig(services: [incoming]))
        #expect(merged.services.count == 1)
        #expect(merged.services[0].id == local.id)
        #expect(merged.services[0].command == "new")
        #expect(merged.services[0].path == "~/new")
    }

    @Test("merge keeps local-only services and appends new ones with a fresh id")
    func mergeAppends() {
        let local = service("auth", "~/a")
        let incoming = service("fe", "~/fe")
        let merged = ConfigTransfer.merge(local: AppConfig(services: [local]), imported: AppConfig(services: [incoming]))
        #expect(merged.services.map(\.name) == ["auth", "fe"])
        #expect(merged.services[1].id != incoming.id)
    }

    @Test("merge combines presets and keeps the local startup settings")
    func mergeSettings() {
        let local = AppConfig(stageTimeoutSeconds: 30, commandPresets: ["yarn dev"], startupMode: .parallel,
                              notifyOnCrash: false)
        let imported = AppConfig(stageTimeoutSeconds: 120, commandPresets: ["pnpm dev", "yarn dev", "pnpm dev"],
                                 startupMode: .staged, notifyOnCrash: true)
        let merged = ConfigTransfer.merge(local: local, imported: imported)
        #expect(merged.commandPresets == ["yarn dev", "pnpm dev"])
        #expect(merged.stageTimeoutSeconds == 30)
        #expect(merged.startupMode == .parallel)
        #expect(merged.notifyOnCrash == false)
    }

    // MARK: replace

    @Test("replace takes the imported config but keeps ids of same-name services")
    func replace() {
        let localAuth = service("auth", "~/a")
        let localOld = service("old", "~/old")
        let imported = AppConfig(services: [service("AUTH", "~/a2"), service("fe", "~/fe")], stageTimeoutSeconds: 120,
                                 commandPresets: ["pnpm dev"], startupMode: .parallel, notifyOnCrash: false)
        let result = ConfigTransfer.replace(local: AppConfig(services: [localAuth, localOld]), imported: imported)
        #expect(result.services.map(\.name) == ["AUTH", "fe"])
        #expect(result.services[0].id == localAuth.id)
        #expect(result.services[0].path == "~/a2")
        #expect(result.services[1].id != localOld.id)
        #expect(result.stageTimeoutSeconds == 120)
        #expect(result.commandPresets == ["pnpm dev"])
        #expect(result.startupMode == .parallel)
        #expect(result.notifyOnCrash == false)
    }

    @Test("replace gives services with duplicate names distinct ids")
    func replaceDuplicates() {
        let local = service("auth", "~/a")
        let imported = AppConfig(services: [service("auth", "~/a"), service("auth", "~/b")])
        let result = ConfigTransfer.replace(local: AppConfig(services: [local]), imported: imported)
        #expect(result.services[0].id == local.id)
        #expect(result.services[1].id != local.id)
    }
}
