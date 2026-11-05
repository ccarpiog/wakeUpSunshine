import Foundation
import SwiftUI
import WakeCore

enum DeviceStatus: Equatable {
    case unknown, checking, online, offline, waking, sent, failed(String)

    var title: String {
        switch self {
        case .unknown: return "Not checked"
        case .checking: return "Checking…"
        case .online: return "Online"
        case .offline: return "Not reachable"
        case .waking: return "Sending…"
        case .sent: return "Wake packet sent"
        case .failed: return "Wake failed"
        }
    }
    var symbol: String {
        switch self {
        case .online: return "checkmark.circle"
        case .checking, .waking: return "arrow.triangle.2.circlepath"
        case .sent: return "sun.max"
        case .failed: return "exclamationmark.triangle"
        case .offline: return "moon.zzz"
        case .unknown: return "desktopcomputer"
        }
    }
    var color: Color {
        switch self {
        case .online: return .green
        case .failed: return .red
        case .sent, .waking: return .orange
        case .checking: return .blue
        default: return .secondary
        }
    }
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let computerName: String
    let message: String
    let isError: Bool
}

@MainActor
final class AppStore: ObservableObject {
    @Published var computers: [Computer] = []
    @Published var selection: Set<UUID> = []
    @Published var focusedID: UUID?
    @Published var searchText = ""
    @Published var selectedGroup: String?
    @Published var statuses: [UUID: DeviceStatus] = [:]
    @Published var activity: [ActivityEntry] = []
    @Published var isWaking = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?

    private let repository: ComputerRepository
    private let demo: Bool
    private var loadFailed = false

    init(demo: Bool = false, fileURL: URL? = nil) {
        self.demo = demo
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        repository = ComputerRepository(fileURL: fileURL ?? support.appendingPathComponent("WakeUpSunshine/computers.json"))
        if demo {
            computers = [
                Computer(name: "Studio Mac", ipAddress: "192.168.1.20", macAddress: "02:11:22:33:44:01", group: "Studio"),
                Computer(name: "Gaming PC", ipAddress: "192.168.1.42", macAddress: "02:11:22:33:44:02", group: "Home", probePort: 47990),
                Computer(name: "Media Server", ipAddress: "192.168.1.10", macAddress: "02:11:22:33:44:03", group: "Home"),
                Computer(name: "Design Workstation", ipAddress: "192.168.1.24", macAddress: "02:11:22:33:44:04", group: "Studio"),
                Computer(name: "Lab Mini", ipAddress: "192.168.1.60", macAddress: "02:11:22:33:44:05", group: "Lab")
            ]
            for (index, computer) in computers.enumerated() {
                statuses[computer.id] = index == 0 || index == 2 ? .online : .offline
            }
            focusedID = computers[1].id
        } else {
            do { computers = try repository.load() }
            catch {
                loadFailed = true
                errorMessage = "Your saved computers could not be loaded. The original file has been preserved. \(error.localizedDescription)"
            }
        }
    }

    var filteredComputers: [Computer] {
        computers.filter { computer in
            (selectedGroup == nil || computer.group == selectedGroup) &&
            (searchText.isEmpty || [computer.name, computer.ipAddress, computer.macAddress, computer.group]
                .contains { $0.localizedCaseInsensitiveContains(searchText) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var selectedComputers: [Computer] { computers.filter { selection.contains($0.id) } }
    var groups: [String] { Array(Set(computers.map(\.group))).sorted() }
    var focusedComputer: Computer? { computers.first { $0.id == focusedID } }

    func saveComputer(_ computer: Computer) throws {
        let validated = try computer.validated()
        guard !computers.contains(where: { $0.id != validated.id && $0.macAddress == validated.macAddress }) else {
            throw StoreError.message("A computer with this MAC address already exists.")
        }
        var updated = computers
        if let index = updated.firstIndex(where: { $0.id == validated.id }) { updated[index] = validated }
        else { updated.append(validated) }
        try persist(updated)
        statuses[validated.id] = .unknown
        focusedID = validated.id
    }

    func deleteComputers(ids: Set<UUID>) throws {
        try persist(computers.filter { !ids.contains($0.id) })
        selection.subtract(ids)
        for id in ids { statuses.removeValue(forKey: id) }
        if let id = focusedID, ids.contains(id) { focusedID = nil }
        if let group = selectedGroup, !groups.contains(group) { selectedGroup = nil }
    }

    @discardableResult
    func importComputers(_ imported: [Computer], replaceExisting: Bool) throws -> Int {
        var updated = computers
        var indexByMAC = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element.macAddress, $0.offset) })
        var count = 0
        var changedIDs: [UUID] = []
        for computer in imported {
            var validated = try computer.validated()
            if let index = indexByMAC[validated.macAddress] {
                guard replaceExisting else { continue }
                validated.id = updated[index].id
                updated[index] = validated
            } else {
                indexByMAC[validated.macAddress] = updated.count
                updated.append(validated)
            }
            changedIDs.append(validated.id)
            count += 1
        }
        try persist(updated)
        for id in changedIDs { statuses[id] = .unknown }
        log("Import", "\(count) computer\(count == 1 ? "" : "s") saved.")
        return count
    }

    func exportCSV() -> String { CSVImporter.export(computers) }

    func wake(_ requested: [Computer]) async {
        guard !isWaking, !requested.isEmpty else { return }
        var seen = Set<UUID>()
        let unique = requested.filter { seen.insert($0.id).inserted }
        isWaking = true
        defer { isWaking = false }
        for computer in unique { statuses[computer.id] = .waking }
        // Keep batch work bounded. UDP transmission runs off the main actor.
        for chunkStart in stride(from: 0, to: unique.count, by: 12) {
            let chunk = Array(unique[chunkStart..<min(chunkStart + 12, unique.count)])
            await withTaskGroup(of: (Computer, String?).self) { group in
                for computer in chunk {
                    let isDemo = demo
                    group.addTask {
                        if isDemo { return (computer, nil) }
                        do {
                            try WakeOnLAN.send(to: computer)
                            return (computer, nil)
                        } catch { return (computer, error.localizedDescription) }
                    }
                }
                for await (computer, failure) in group {
                    guard computers.contains(computer) else { continue }
                    let id = computer.id
                    let name = computer.name
                    if let failure {
                        statuses[id] = .failed(failure)
                        log(name, failure, isError: true)
                    } else {
                        statuses[id] = .sent
                        log(name, demo ? "Demo: wake simulated. No packet sent." : "Magic packet sent. Waiting for the computer to become reachable.")
                    }
                }
            }
        }
    }

    func refresh() async {
        guard !isRefreshing, !isWaking, !demo else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = computers
        for chunkStart in stride(from: 0, to: snapshot.count, by: 16) {
            if Task.isCancelled { return }
            let chunk = Array(snapshot[chunkStart..<min(chunkStart + 16, snapshot.count)])
            await withTaskGroup(of: (Computer, Bool).self) { group in
                for computer in chunk {
                    if statuses[computer.id] == nil || statuses[computer.id] == .unknown { statuses[computer.id] = .checking }
                    group.addTask { (computer, await Reachability.check(computer)) }
                }
                for await (computer, online) in group {
                    guard computers.contains(computer), !isWaking else { continue }
                    let previous = statuses[computer.id]
                    // A failed probe does not undo evidence that the wake packet was sent.
                    if online {
                        statuses[computer.id] = .online
                        if previous == .sent { log(computer.name, "Online — probe port \(computer.probePort) responded.") }
                    } else if previous != .sent && previous != .waking {
                        if case .failed = previous { continue }
                        statuses[computer.id] = .offline
                    }
                }
            }
        }
    }

    private func persist(_ updated: [Computer]) throws {
        guard !loadFailed else {
            throw StoreError.message("Saving is paused to protect the unreadable computers.json file in Application Support/WakeUpSunshine. Restore or move that file, then reopen the app.")
        }
        if !demo { try repository.save(updated) }
        computers = updated
    }

    private func log(_ name: String, _ message: String, isError: Bool = false) {
        activity.insert(ActivityEntry(computerName: name, message: message, isError: isError), at: 0)
        if activity.count > 300 { activity.removeLast(activity.count - 300) }
    }
}

private enum StoreError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
