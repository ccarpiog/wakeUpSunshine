import Foundation

public struct ComputerRepository: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> [Computer] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let computers = try JSONDecoder().decode([Computer].self, from: data)
        return try validated(computers)
    }

    public func save(_ computers: [Computer]) throws {
        let validated = try validated(computers)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private func validated(_ computers: [Computer]) throws -> [Computer] {
        var ids = Set<UUID>(), macs = Set<String>()
        return try computers.map { raw in
            let computer = try raw.validated()
            guard ids.insert(computer.id).inserted, macs.insert(computer.macAddress).inserted else {
                throw WakeError.invalid("The computer library contains duplicate IDs or MAC addresses.")
            }
            return computer
        }
    }
}
