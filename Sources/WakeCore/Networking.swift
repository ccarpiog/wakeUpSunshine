import Foundation
import Darwin

public enum WakeOnLAN {
    public static func magicPacket(macAddress: String) throws -> Data {
        let normalized = try Computer.normalizeMAC(macAddress)
        let bytes = normalized.split(separator: ":").map { UInt8($0, radix: 16)! }
        var packet = Data(repeating: 0xff, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    /// Sends three standard magic packets. Successful transmission is not confirmation that a computer woke.
    public static func send(to computer: Computer) throws {
        let computer = try computer.validated()
        let packet = try magicPacket(macAddress: computer.macAddress)
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw socketError("Cannot create UDP socket") }
        defer { close(fd) }
        var enabled: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw socketError("Cannot enable broadcast")
        }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        guard setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            throw socketError("Cannot set send timeout")
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = computer.wakePort.bigEndian
        guard inet_pton(AF_INET, computer.broadcastAddress, &address.sin_addr) == 1 else {
            throw WakeError.invalid("Invalid destination address.")
        }
        for _ in 0..<3 {
            let sent = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { destination in
                        sendto(fd, bytes.baseAddress, bytes.count, 0, destination, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent == packet.count else { throw socketError("Could not send wake packet") }
        }
    }

    private static func socketError(_ message: String) -> WakeError {
        .network("\(message): \(String(cString: strerror(errno))).")
    }
}

public enum Reachability {
    /// Checks the configured TCP service, with a 1.2-second deadline. A closed or blocked port returns false.
    public static func check(_ computer: Computer) async -> Bool {
        guard let computer = try? computer.validated(), !Task.isCancelled else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: probe(address: computer.ipAddress, port: computer.probePort))
            }
        }
    }

    private static func probe(address: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { return false }
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        guard inet_pton(AF_INET, address, &destination.sin_addr) == 1 else { return false }
        let result = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&descriptor, 1, 1200) > 0 else { return false }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0
    }
}
