import Foundation

public struct ImportIssue: Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public let row: Int
    public let message: String
    public init(row: Int, message: String) { self.row = row; self.message = message }
}

public struct ImportPreview: Sendable {
    public let computers: [Computer]
    public let issues: [ImportIssue]
    public let duplicateCount: Int
    public init(computers: [Computer], issues: [ImportIssue], duplicateCount: Int) {
        self.computers = computers; self.issues = issues; self.duplicateCount = duplicateCount
    }
}

public enum CSVImporter {
    private struct Row { let line: Int; let fields: [String] }
    private static func key(_ text: String) -> String? {
        let value = text.lowercased().filter { $0.isLetter || $0.isNumber }
        switch value {
        case "name", "computer", "computername", "hostname", "devicename": return "name"
        case "ip", "ipaddress", "ipv4", "address": return "ip"
        case "mac", "macaddress", "hardwareaddress", "physicaladdress": return "mac"
        case "group", "room", "location": return "group"
        case "broadcast", "broadcastaddress": return "broadcast"
        case "wakeport", "wolport", "udpport": return "wakeport"
        case "probeport", "tcpport": return "probeport"
        default: return nil
        }
    }

    public static func parse(_ text: String) throws -> ImportPreview {
        guard text.utf8.count <= 10 * 1024 * 1024 else { throw WakeError.invalid("Import is limited to 10 MB.") }
        var source = text
        if source.first == "\u{FEFF}" { source.removeFirst() }
        let rows = try tokenize(source, delimiter: delimiter(in: source))
        guard let first = rows.first else { throw WakeError.invalid("The file contains no computers.") }
        let recognized = first.fields.compactMap(key)
        // A headerless computer may itself be named “Mac” and belong to “Room”.
        // An actual IPv4 value in its second column distinguishes that data row.
        let firstLooksLikeData = first.fields.count >= 3 && Computer.isIPv4(first.fields[1].trimmingCharacters(in: .whitespacesAndNewlines))
        let hasHeader = recognized.count >= 2 && !firstLooksLikeData
        guard rows.count - (hasHeader ? 1 : 0) <= 10000 else {
            throw WakeError.invalid("Import is limited to 10,000 computers.")
        }
        var indexes: [String: Int] = [:]
        if hasHeader {
            for (index, field) in first.fields.enumerated() {
                guard let mapped = key(field) else { continue }
                guard indexes[mapped] == nil else { throw WakeError.invalid("Header contains duplicate column ‘\(field)’.") }
                indexes[mapped] = index
            }
            guard ["name", "ip", "mac"].allSatisfy({ indexes[$0] != nil }) else {
                throw WakeError.invalid("Header must include name, IP address and MAC address columns.")
            }
        } else {
            indexes = ["name": 0, "ip": 1, "mac": 2, "group": 3]
        }
        var computers: [Computer] = [], issues: [ImportIssue] = []
        var seen = Set<String>(), duplicates = 0
        for row in rows.dropFirst(hasHeader ? 1 : 0) {
            do {
                guard hasHeader ? row.fields.count == first.fields.count : (3...4).contains(row.fields.count) else {
                    throw WakeError.invalid(hasHeader ? "Expected \(first.fields.count) columns, found \(row.fields.count)." : "Without a header, use name, IP, MAC and an optional group column.")
                }
                func field(_ key: String, default fallback: String = "") -> String {
                    guard let index = indexes[key], index < row.fields.count else { return fallback }
                    let value = row.fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? fallback : value
                }
                func port(_ key: String, default fallback: UInt16) throws -> UInt16 {
                    let value = field(key)
                    if value.isEmpty { return fallback }
                    guard value.allSatisfy({ $0 >= "0" && $0 <= "9" }), let number = UInt16(value), number > 0 else {
                        throw WakeError.invalid("\(key == "wakeport" ? "Wake" : "Probe") port must be between 1 and 65535.")
                    }
                    return number
                }
                let computer = try Computer(name: field("name"), ipAddress: field("ip"), macAddress: field("mac"),
                                            group: field("group", default: "General"),
                                            broadcastAddress: field("broadcast", default: "255.255.255.255"),
                                            wakePort: port("wakeport", default: 9), probePort: port("probeport", default: 22)).validated()
                guard seen.insert(computer.macAddress).inserted else {
                    duplicates += 1
                    throw WakeError.invalid("Duplicate MAC address \(computer.macAddress); the first valid row is kept.")
                }
                computers.append(computer)
            } catch { issues.append(ImportIssue(row: row.line, message: error.localizedDescription)) }
        }
        return ImportPreview(computers: computers, issues: issues, duplicateCount: duplicates)
    }

    public static func export(_ computers: [Computer]) -> String {
        func escape(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func spreadsheetText(_ value: String) -> String {
            // CSV quoting alone does not keep spreadsheet software from interpreting a formula.
            // Check past whitespace as some spreadsheet importers discard it before evaluation.
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first, "=+-@".contains(first) else { return value }
            return "'" + value
        }
        var lines = ["name,ip,mac,group,broadcast,wake_port,probe_port"]
        lines += computers.map { computer in
            [spreadsheetText(computer.name), computer.ipAddress, computer.macAddress, spreadsheetText(computer.group), computer.broadcastAddress,
             String(computer.wakePort), String(computer.probePort)].map(escape).joined(separator: ",")
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func delimiter(in text: String) -> Character {
        var quoted = false
        var hasContent = false
        var counts: [Character: Int] = [",": 0, "\t": 0, ";": 0]
        for character in text {
            if character == "\"" { quoted.toggle() }
            if !quoted {
                if character == "\n" || character == "\r\n" || character == "\r" {
                    if hasContent { break }
                    continue
                }
                if counts[character] != nil { counts[character, default: 0] += 1 }
            }
            if !character.isWhitespace { hasContent = true }
        }
        let candidates: [Character] = [",", "\t", ";"]
        return candidates.reduce(Character(",")) { best, candidate in
            counts[candidate, default: 0] > counts[best, default: 0] ? candidate : best
        }
    }

    private static func tokenize(_ source: String, delimiter: Character) throws -> [Row] {
        let chars = Array(source)
        var rows: [Row] = [], fields: [String] = [], field = ""
        var inQuotes = false, closedQuote = false, index = 0, line = 1, startLine = 1
        func appendRow() {
            fields.append(field)
            if fields.count > 1 || !fields[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows.append(Row(line: startLine, fields: fields))
            }
            field = ""; fields = []; closedQuote = false
        }
        while index < chars.count {
            let character = chars[index]
            let newline = character == "\n" || character == "\r" || character == "\r\n"
            if inQuotes {
                if character == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { inQuotes = false; closedQuote = true }
                } else { field.append(character); if newline { line += 1 } }
            } else if character == delimiter {
                fields.append(field); field = ""; closedQuote = false
            } else if newline {
                appendRow(); line += 1; startLine = line
            } else if character == "\"" {
                guard field.isEmpty && !closedQuote else { throw WakeError.invalid("Malformed quote on line \(line). Quote the whole field and double quotes inside it.") }
                inQuotes = true
            } else if closedQuote {
                guard character == " " || character == "\t" else { throw WakeError.invalid("Unexpected text after a closing quote on line \(line).") }
            } else { field.append(character) }
            index += 1
        }
        guard !inQuotes else { throw WakeError.invalid("Unclosed quoted field beginning on line \(startLine).") }
        if !field.isEmpty || !fields.isEmpty || closedQuote { appendRow() }
        return rows
    }
}
