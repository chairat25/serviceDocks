import Foundation
import ServiceDockCore

/// Runs `ps` off the main thread and returns CPU/RAM per process group.
enum StatsSampler {
    static func sample() async -> [Int32: ProcessStats.Sample] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ProcessStats.psArguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                logger.error("ps failed: \(error.localizedDescription, privacy: .public)")
                return [:]
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ProcessStats.parse(String(decoding: data, as: UTF8.self))
        }.value
    }
}
