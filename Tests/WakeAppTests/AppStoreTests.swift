import XCTest
import WakeCore
@testable import WakeUpSunshine

final class AppStoreTests: XCTestCase {
    private func computer(_ number: Int, group: String = "General") -> Computer {
        Computer(name: "Computer \(number)", ipAddress: "192.168.1.\(number)",
                 macAddress: String(format: "02:11:22:33:44:%02X", number), group: group)
    }

    @MainActor
    func testCustomOrderPersistsReloadsAndExportsWithoutChangingSelectionOrStatus() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("computers.json")
        let store = AppStore(fileURL: url)
        let originals = (1...4).map { computer($0) }
        try store.importComputers(originals, replaceExisting: false)
        store.selection = [originals[0].id, originals[3].id]
        store.focusedID = originals[0].id
        store.statuses[originals[0].id] = .online
        try store.moveComputers(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        let expected = [originals[1], originals[3], originals[0], originals[2]]
        XCTAssertEqual(store.filteredComputers, expected)
        XCTAssertEqual(AppStore(fileURL: url).filteredComputers, expected)
        XCTAssertEqual(try CSVImporter.parse(store.exportCSV()).computers.map(\.name), expected.map(\.name))
        XCTAssertEqual(store.selection, [originals[0].id, originals[3].id])
        XCTAssertEqual(store.focusedID, originals[0].id)
        XCTAssertEqual(store.statuses[originals[0].id], .online)
    }

    @MainActor
    func testFilteredReorderKeepsHiddenComputersInTheirSlots() throws {
        let store = AppStore(demo: true)
        let originals = store.computers
        store.selectedGroup = "Studio"
        XCTAssertEqual(store.filteredComputers, [originals[0], originals[3]])
        try store.moveComputers(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(store.computers, [originals[3], originals[1], originals[2], originals[0], originals[4]])
        store.selectedGroup = nil
        store.searchText = "192.168.1.2"
        XCTAssertEqual(store.filteredComputers, [originals[3], originals[0]])
        try store.moveComputer(id: originals[0].id, direction: -1)
        XCTAssertEqual(store.computers, originals)
    }

    @MainActor
    func testMoveBoundariesAndInvalidOffsetsAreSafeNoOps() throws {
        let store = AppStore(demo: true)
        let originals = store.computers
        XCTAssertFalse(store.canMoveComputer(id: originals[0].id, direction: -1))
        XCTAssertFalse(store.canMoveComputer(id: originals[4].id, direction: 1))
        XCTAssertFalse(store.canMoveComputer(id: UUID(), direction: 1))
        XCTAssertFalse(store.canMoveComputer(id: originals[2].id, direction: Int.max))
        try store.moveComputer(id: originals[0].id, direction: -1)
        try store.moveComputer(id: originals[4].id, direction: 1)
        try store.moveComputers(fromOffsets: IndexSet(integer: 100), toOffset: 0)
        try store.moveComputers(fromOffsets: IndexSet(integer: 0), toOffset: -1)
        try store.moveComputers(fromOffsets: [], toOffset: 0)
        XCTAssertEqual(store.computers, originals)
        try store.moveComputer(id: originals[0].id, direction: 1)
        XCTAssertEqual(store.computers.prefix(2), [originals[1], originals[0]])
    }

    @MainActor
    func testUpdatingAndImportingPreserveCustomOrder() throws {
        let store = AppStore(demo: true)
        try store.moveComputer(id: store.computers[0].id, direction: 1)
        let orderedIDs = store.computers.map(\.id)
        var changed = store.computers[1]
        changed.name = "A renamed computer"
        try store.saveComputer(changed)
        changed.id = UUID()
        changed.name = "Updated from import"
        let appended = computer(90)
        try store.importComputers([changed, appended], replaceExisting: true)
        XCTAssertEqual(store.computers.map(\.id), orderedIDs + [appended.id])
        XCTAssertEqual(store.filteredComputers[1].name, "Updated from import")
    }

    @MainActor
    func testFailedOrderSaveLeavesPublishedOrderUnchangedAndNoOpDoesNotWrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("computers.json")
        let store = AppStore(fileURL: url)
        let originals = [computer(1), computer(2)]
        try store.importComputers(originals, replaceExisting: false)
        try FileManager.default.removeItem(at: folder)
        try Data("block directory creation".utf8).write(to: folder)
        XCTAssertThrowsError(try store.moveComputers(fromOffsets: [0], toOffset: 2))
        XCTAssertEqual(store.computers, originals)
        XCTAssertNoThrow(try store.moveComputers(fromOffsets: [0], toOffset: 1))
        XCTAssertEqual(store.computers, originals)
    }

    @MainActor
    func testImportSkipAndReplacePreservesIdentityAndPersistence() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("computers.json")
        let store = AppStore(fileURL: url)
        let first = Computer(name: "Original", ipAddress: "192.168.1.5", macAddress: "02:11:22:33:44:55")
        try store.saveComputer(first)
        let replacement = Computer(name: "Updated", ipAddress: "192.168.1.6", macAddress: "021122334455", group: "Lab")
        XCTAssertEqual(try store.importComputers([replacement], replaceExisting: false), 0)
        XCTAssertEqual(store.computers.first?.name, "Original")
        XCTAssertEqual(try store.importComputers([replacement], replaceExisting: true), 1)
        XCTAssertEqual(store.computers.first?.id, first.id)
        XCTAssertEqual(store.computers.first?.name, "Updated")
        XCTAssertEqual(AppStore(fileURL: url).computers, store.computers)
    }

    @MainActor
    func testInvalidImportIsAtomic() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(fileURL: folder.appendingPathComponent("computers.json"))
        let valid = Computer(name: "Valid", ipAddress: "192.168.1.5", macAddress: "02:11:22:33:44:55")
        let invalid = Computer(name: "Invalid", ipAddress: "bad", macAddress: "02:11:22:33:44:56")
        XCTAssertThrowsError(try store.importComputers([valid, invalid], replaceExisting: false))
        XCTAssertTrue(store.computers.isEmpty)
    }

    @MainActor
    func testCorruptFileCannotBeOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("computers.json")
        let original = Data("broken saved content".utf8)
        try original.write(to: url)
        let store = AppStore(fileURL: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertThrowsError(try store.saveComputer(Computer(name: "New", ipAddress: "192.168.1.5", macAddress: "02:11:22:33:44:55")))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testSelectionPersistsAcrossFiltersAndDeletionCleansSelection() throws {
        let store = AppStore(demo: true)
        let selected = store.computers[0]
        store.selection = [selected.id]
        store.focusedID = selected.id
        store.searchText = "No such computer"
        XCTAssertTrue(store.filteredComputers.isEmpty)
        XCTAssertEqual(store.selectedComputers, [selected])
        try store.deleteComputers(ids: [selected.id])
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertNil(store.focusedID)
    }

    @MainActor
    func testDemoWakeReportsSimulationAndDoesNotPersist() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(demo: true, fileURL: url)
        let requested = Array(store.computers.prefix(3))
        await store.wake(requested + requested)
        XCTAssertFalse(store.isWaking)
        XCTAssertEqual(store.activity.count, 3)
        for computer in requested { XCTAssertEqual(store.statuses[computer.id], .sent) }
        XCTAssertTrue(store.activity.allSatisfy { $0.message.contains("simulated") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
