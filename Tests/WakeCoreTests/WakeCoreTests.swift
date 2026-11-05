import XCTest
import Darwin
@testable import WakeCore

final class WakeCoreTests: XCTestCase {
    private func computer(mac: String = "02:11:22:33:44:55") -> Computer {
        Computer(name: "Studio", ipAddress: "192.168.1.42", macAddress: mac)
    }

    func testMACNormalizationAndRejection() throws {
        for value in ["021122334455", "02-11-22-33-44-55", "0211.2233.4455", " 02:11:22:33:44:55 "] {
            XCTAssertEqual(try Computer.normalizeMAC(value), "02:11:22:33:44:55")
        }
        for value in ["", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "01:11:22:33:44:55", "02:11:22:33:44:GG", "02:1122:33:44:55", "02-11:22:33:44:55", "02 11 22 33 44 55"] {
            XCTAssertThrowsError(try Computer.normalizeMAC(value), value)
        }
    }

    func testComputerValidation() throws {
        var item = computer()
        item.name = "  Main workstation  "
        item.group = " "
        item.macAddress = "021122334455"
        let validated = try item.validated()
        XCTAssertEqual(validated.name, "Main workstation")
        XCTAssertEqual(validated.group, "General")
        XCTAssertEqual(validated.macAddress, "02:11:22:33:44:55")
        for address in ["256.1.1.1", "1.2.3", "01.2.3.4", "0.0.0.0", "224.0.0.1", "255.255.255.255", "localhost", "1.2.3.4 "] {
            item.ipAddress = address
            if address.hasSuffix(" ") { XCTAssertNoThrow(try item.validated()) }
            else { XCTAssertThrowsError(try item.validated(), address) }
        }
        item = computer(); item.name = "\n"; XCTAssertThrowsError(try item.validated())
        item = computer(); item.name = "Line\nBreak"; XCTAssertThrowsError(try item.validated())
        item = computer(); item.name = String(repeating: "x", count: 129); XCTAssertThrowsError(try item.validated())
        item = computer(); item.wakePort = 0; XCTAssertThrowsError(try item.validated())
        item = computer(); item.probePort = 0; XCTAssertThrowsError(try item.validated())
        item = computer(); item.broadcastAddress = "224.0.0.1"; XCTAssertThrowsError(try item.validated())
    }

    func testCSVQuotedFieldsAliasesAndBOM() throws {
        let preview = try CSVImporter.parse("\u{FEFF}Computer Name,IP Address,MAC Address,Group,Broadcast Address,Wake Port,Probe Port\r\n\"Studio, \"\"A\"\"\",192.168.1.42,021122334455,Office,192.168.1.255,7,47989\r\n")
        XCTAssertTrue(preview.issues.isEmpty)
        let item = try XCTUnwrap(preview.computers.first)
        XCTAssertEqual(item.name, "Studio, \"A\"")
        XCTAssertEqual(item.group, "Office")
        XCTAssertEqual(item.wakePort, 7)
        XCTAssertEqual(item.probePort, 47989)
        XCTAssertEqual(item.broadcastAddress, "192.168.1.255")
    }

    func testTSVAndSemicolonAndHeaderless() throws {
        for delimiter in ["\t", ";", ","] {
            let source = "\n\n" + ["name", "ip", "mac"].joined(separator: delimiter) + "\n" + ["Workstation", "192.168.1.5", "021122334455"].joined(separator: delimiter)
            XCTAssertEqual(try CSVImporter.parse(source).computers.count, 1)
        }
        let result = try CSVImporter.parse("Workstation,192.168.1.5,021122334455,Lab\nSecond,192.168.1.6,021122334456")
        XCTAssertEqual(result.computers.map(\.group), ["Lab", "General"])
        for name in ["Mac", "IP", "Name", "Computer"] {
            XCTAssertEqual(try CSVImporter.parse("\(name),192.168.1.5,021122334455").computers.first?.name, name)
        }
        XCTAssertEqual(try CSVImporter.parse("Mac,192.168.1.5,021122334455,Room").computers.first?.group, "Room")
    }

    func testImportRejectsBadRowsAndReportsPhysicalLines() throws {
        let result = try CSVImporter.parse("name,ip,mac\nGood,192.168.1.2,021122334455\nBad,999.1.1.1,021122334456\n\"Two\nlines\",192.168.1.3,021122334457\nMissing,192.168.1.4\n,,\n")
        XCTAssertEqual(result.computers.count, 1)
        XCTAssertEqual(result.issues.map(\.row), [3, 4, 6, 7])
    }

    func testDuplicatesUseCanonicalMACAndKeepFirstValidRow() throws {
        let result = try CSVImporter.parse("name,ip,mac\nBad,999.1.1.1,021122334455\nFirst,192.168.1.2,02:11:22:33:44:55\nSecond,192.168.1.3,02-11-22-33-44-55")
        XCTAssertEqual(result.computers.map(\.name), ["First"])
        XCTAssertEqual(result.duplicateCount, 1)
        XCTAssertEqual(result.issues.map(\.row), [2, 4])
    }

    func testMalformedFramingAndHeadersThrow() {
        for source in ["name,ip,mac\n\"unclosed,192.168.1.1,021122334455", "name,ip,mac\n\"closed\"junk,192.168.1.1,021122334455", "name,ip,mac\nnot\"quoted,192.168.1.1,021122334455", "name,ip,ip,mac\n", "name,ip\n", " \n\n"] {
            XCTAssertThrowsError(try CSVImporter.parse(source), source)
        }
    }

    func testPortsMustBeValidAndExportRoundTrips() throws {
        let parsed = try CSVImporter.parse("name,ip,mac,wake_port,probe_port\nA,192.168.1.2,021122334455,0,22\nB,192.168.1.3,021122334456,9,65536\nC,192.168.1.4,021122334457,9,abc\nD,192.168.1.5,021122334458,,")
        XCTAssertEqual(parsed.issues.count, 3)
        XCTAssertEqual(parsed.computers.count, 1)
        var original = computer(); original.name = "A, \"quoted\" computer"; original.group = "Design, Lab"; original.probePort = 47989
        let roundTripped = try XCTUnwrap(CSVImporter.parse(CSVImporter.export([original])).computers.first)
        XCTAssertEqual(roundTripped.name, original.name)
        XCTAssertEqual(roundTripped.group, original.group)
        XCTAssertEqual(roundTripped.probePort, original.probePort)
    }

    func testMagicPacketContainsExactlySixFFAndSixteenMACs() throws {
        let packet = try WakeOnLAN.magicPacket(macAddress: "021122334455")
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), [UInt8](repeating: 255, count: 6))
        for index in 0..<16 { XCTAssertEqual(Array(packet[(6 + index * 6)..<(12 + index * 6)]), [2, 17, 34, 51, 68, 85]) }
        XCTAssertThrowsError(try WakeOnLAN.magicPacket(macAddress: "bad"))
    }

    func testImportLimitCountsDataRowsWithAndWithoutHeader() throws {
        let row = "Studio,192.168.1.42,021122334455\n"
        let atLimit = String(repeating: row, count: 10000)
        let overLimit = atLimit + row
        for header in ["", "name,ip,mac\n"] {
            let preview = try CSVImporter.parse(header + atLimit)
            XCTAssertEqual(preview.computers.count, 1)
            XCTAssertEqual(preview.duplicateCount, 9999)
            XCTAssertThrowsError(try CSVImporter.parse(header + overLimit))
        }
    }

    func testExportNeutralizesFormulaLeadingNamesAndGroups() throws {
        for marker in ["=", "+", "-", "@"] {
            var item = computer()
            item.name = marker + "Inventory"
            item.group = marker + "Group"
            let parsed = try XCTUnwrap(CSVImporter.parse(CSVImporter.export([item])).computers.first)
            XCTAssertEqual(parsed.name, "'" + item.name)
            XCTAssertEqual(parsed.group, "'" + item.group)
            XCTAssertEqual(parsed.ipAddress, item.ipAddress)
            XCTAssertEqual(parsed.macAddress, item.macAddress)
        }
        var item = computer()
        item.name = "  =Inventory"
        item.group = "\t+Group"
        let output = CSVImporter.export([item])
        XCTAssertTrue(output.contains("\"'  =Inventory\""))
        XCTAssertTrue(output.contains("\"'\t+Group\""))
        item.name = "Ordinary, \"quoted\" workstation"
        item.group = "Design lab"
        let normal = try XCTUnwrap(CSVImporter.parse(CSVImporter.export([item])).computers.first)
        XCTAssertEqual(normal.name, item.name)
        XCTAssertEqual(normal.group, item.group)
    }

    func testActualUDPSendUsesConfiguredDestinationPortAndPayload() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0)
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        XCTAssertEqual(withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }, 0)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        XCTAssertEqual(setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)), 0)
        var item = computer(); item.broadcastAddress = "127.0.0.1"; item.wakePort = UInt16(bigEndian: address.sin_port)
        try WakeOnLAN.send(to: item)
        for _ in 0..<3 {
            var received = [UInt8](repeating: 0, count: 2048)
            let length = recv(fd, &received, received.count, 0)
            XCTAssertEqual(length, 102)
            if length > 0 { XCTAssertEqual(Data(received.prefix(length)), try WakeOnLAN.magicPacket(macAddress: item.macAddress)) }
        }
    }

    func testRepositoryAtomicRoundTripAndCorruptionIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ComputerRepository(fileURL: directory.appendingPathComponent("nested/computers.json"))
        XCTAssertEqual(try repository.load(), [])
        let item = try computer().validated()
        try repository.save([item]); XCTAssertEqual(try repository.load(), [item])
        XCTAssertThrowsError(try repository.save([item, item]))
        XCTAssertEqual(try repository.load(), [item])
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), corrupt)
        let duplicated = try JSONEncoder().encode([item, item]); try duplicated.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        var invalid = item; invalid.ipAddress = "bad"
        try JSONEncoder().encode([invalid]).write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
    }

    func testTCPProbeRecognizesListeningServiceAndClosedPort() async throws {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        defer { close(fd) }
        XCTAssertGreaterThanOrEqual(fd, 0)
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        XCTAssertEqual(withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }, 0)
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        XCTAssertEqual(withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }, 0)
        var item = computer(); item.ipAddress = "127.0.0.1"; item.probePort = UInt16(bigEndian: address.sin_port)
        let closed = await Reachability.check(item); XCTAssertFalse(closed)
        XCTAssertEqual(listen(fd, 4), 0)
        let online = await Reachability.check(item); XCTAssertTrue(online)
    }
}
