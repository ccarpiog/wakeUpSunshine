import XCTest
import WakeCore
@testable import WakeUpSunshine

final class AppStoreTests: XCTestCase {
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
