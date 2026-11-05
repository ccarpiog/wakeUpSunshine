import Foundation
import Darwin

public enum WakeError: LocalizedError, Equatable {
    case invalid(String)
    case network(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message), .network(let message): return message }
    }
}

public struct Computer: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var ipAddress: String
    public var macAddress: String
    public var group: String
    public var broadcastAddress: String
    public var wakePort: UInt16
    public var probePort: UInt16

    public init(id: UUID = UUID(), name: String, ipAddress: String, macAddress: String,
                group: String = "General", broadcastAddress: String = "255.255.255.255",
                wakePort: UInt16 = 9, probePort: UInt16 = 22) {
        self.id = id; self.name = name; self.ipAddress = ipAddress; self.macAddress = macAddress
        self.group = group; self.broadcastAddress = broadcastAddress
        self.wakePort = wakePort; self.probePort = probePort
    }

    public func validated() throws -> Computer {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.group = group.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.ipAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.broadcastAddress = broadcastAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.name.isEmpty, copy.name.count <= 128,
              !copy.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw WakeError.invalid("Name must contain 1–128 characters and no control characters.")
        }
        if copy.group.isEmpty { copy.group = "General" }
        guard copy.group.count <= 80,
              !copy.group.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw WakeError.invalid("Group must contain at most 80 characters and no control characters.")
        }
        guard Self.isIPv4(copy.ipAddress), let first = Int(copy.ipAddress.split(separator: ".")[0]), first > 0, first < 224 else {
            throw WakeError.invalid("IP address must be a valid unicast IPv4 address (for example, 192.168.1.10).")
        }
        guard Self.isIPv4(copy.broadcastAddress), copy.broadcastAddress != "0.0.0.0" else {
            throw WakeError.invalid("Broadcast address must be a valid IPv4 address.")
        }
        let broadcastFirst = Int(copy.broadcastAddress.split(separator: ".")[0])!
        guard broadcastFirst < 224 || copy.broadcastAddress == "255.255.255.255" else {
            throw WakeError.invalid("Broadcast address cannot be a multicast address.")
        }
        copy.macAddress = try Self.normalizeMAC(macAddress)
        guard wakePort > 0, probePort > 0 else { throw WakeError.invalid("Ports must be between 1 and 65535.") }
        return copy
    }

    public static func isIPv4(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let value = Int(part), value <= 255 else { return false }
            return part.count == 1 || part.first != "0"
        }
    }

    public static func normalizeMAC(_ input: String) throws -> String {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact: String
        if raw.contains(":") || raw.contains("-") {
            let separator: Character = raw.contains(":") ? ":" : "-"
            let parts = raw.split(separator: separator, omittingEmptySubsequences: false)
            guard parts.count == 6, parts.allSatisfy({ $0.count == 2 }) else {
                throw WakeError.invalid("MAC address must contain six hexadecimal byte pairs.")
            }
            compact = parts.joined()
        } else if raw.contains(".") {
            let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, parts.allSatisfy({ $0.count == 4 }) else {
                throw WakeError.invalid("Dotted MAC address must contain three groups of four hexadecimal digits.")
            }
            compact = parts.joined()
        } else { compact = raw }
        guard compact.utf8.count == 12, compact.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw WakeError.invalid("MAC address must contain exactly 12 hexadecimal digits.")
        }
        let chars = Array(compact)
        let bytes = stride(from: 0, to: 12, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! }
        guard bytes.contains(where: { $0 != 0 }), bytes[0] & 1 == 0 else {
            throw WakeError.invalid("MAC address must identify one computer; zero, multicast and broadcast addresses are not allowed.")
        }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
