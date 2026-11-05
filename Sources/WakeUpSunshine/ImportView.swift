import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WakeCore

struct ImportView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var preview: ImportPreview?
    @State private var error: String?
    @State private var fileName: String?
    @State private var replaceExisting = false
    @State private var importedCount: Int?

    private var existingCount: Int {
        let existing = Set(store.computers.map(\.macAddress))
        return preview?.computers.filter { existing.contains($0.macAddress) }.count ?? 0
    }
    private var newCount: Int { max(0, (preview?.computers.count ?? 0) - existingCount) }
    private var importCount: Int { replaceExisting ? (preview?.computers.count ?? 0) : newCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 28)).foregroundStyle(Sunshine.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bring your computers together").font(.title2.bold())
                    Text("Import CSV, TSV, or rows copied from your spreadsheet.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let importedCount {
                success(importedCount)
            } else if let preview {
                previewContent(preview)
            } else {
                inputContent
            }
            if let error { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                if preview != nil && importedCount == nil { Button("Back") { preview = nil; error = nil } }
                Spacer()
                Button(importedCount == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
                if importedCount == nil {
                    if preview != nil {
                        Button("Import \(importCount) computer\(importCount == 1 ? "" : "s")", action: commit).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(importCount == 0)
                    } else {
                        Button("Review import", action: review).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }.padding(26).frame(width: 720)
    }

    private var inputContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: openFile) { Label("Choose file…", systemImage: "doc") }.buttonStyle(.bordered)
                Button { if let value = NSPasteboard.general.string(forType: .string) { text = value; fileName = "Clipboard"; error = nil } } label: { Label("Paste clipboard", systemImage: "clipboard") }
                Spacer()
                if let fileName { Text(fileName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            TextEditor(text: $text).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 230).background(Sunshine.subtle, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .accessibilityLabel("Computer data to import")
            VStack(alignment: .leading, spacing: 7) {
                Text("Start with name, IP address, and MAC address.").font(.system(size: 12, weight: .medium))
                Text("name,ip,mac,group\nStudio PC,192.168.1.42,02:11:22:33:44:55,Office").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Headers are optional. Extra columns: broadcast, wake_port, probe_port. Comma, tab, and semicolon separators are supported.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Use example") { text = "name,ip,mac,group\nStudio PC,192.168.1.42,02:11:22:33:44:55,Office\nMedia server,192.168.1.50,02:11:22:33:44:66,Home"; fileName = "Example data" }.buttonStyle(.link).font(.caption)
        }
    }

    private func previewContent(_ preview: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                summary("\(preview.computers.count)", "Valid computers", .green)
                summary("\(existingCount)", "Already saved", Sunshine.accent)
                summary("\(preview.issues.count)", "Rows excluded", preview.issues.isEmpty ? .secondary : .red)
                Spacer()
            }.padding(16).background(Sunshine.subtle, in: RoundedRectangle(cornerRadius: 12))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack { Text("COMPUTER").frame(maxWidth: .infinity, alignment: .leading); Text("IP ADDRESS").frame(width: 120, alignment: .leading); Text("MAC ADDRESS").frame(width: 160, alignment: .leading) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).padding(.vertical, 10)
                    ForEach(preview.computers) { computer in
                        HStack { VStack(alignment: .leading, spacing: 3) { Text(computer.name).fontWeight(.medium); Text(computer.group).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading); Text(computer.ipAddress).font(.system(size: 11).monospaced()).frame(width: 120, alignment: .leading); Text(computer.macAddress).font(.system(size: 11).monospaced()).frame(width: 160, alignment: .leading) }.padding(.vertical, 9)
                        Divider()
                    }
                }.padding(.horizontal, 10)
            }.frame(height: 190).background(Sunshine.subtle, in: RoundedRectangle(cornerRadius: 10))
            if !preview.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("These rows will not be imported").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                    ScrollView { LazyVStack(alignment: .leading, spacing: 5) { ForEach(preview.issues) { issue in Text("Row \(issue.row): \(issue.message)").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) } } }.frame(maxHeight: 90)
                }
            }
            if existingCount > 0 {
                Toggle("Update existing computers with matching MAC addresses", isOn: $replaceExisting).font(.system(size: 12))
                Text(replaceExisting ? "\(existingCount) saved entries will be updated. Their selections are preserved." : "\(existingCount) already saved computers will be skipped.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Review the list before importing. No packets are sent during import.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func success(_ count: Int) -> some View {
        VStack(spacing: 15) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("\(count) computer\(count == 1 ? "" : "s") imported").font(.title2.bold())
            Text("Select your computers in the sidebar and let the day begin.").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 70)
    }
    private func summary(_ number: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(number).font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(color); Text(label).font(.caption).foregroundStyle(.secondary) }
    }
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attrs[.size] as? Int ?? 0) <= 10_000_000 else { error = "Choose a file smaller than 10 MB."; return }
            text = try String(contentsOf: url, encoding: .utf8); fileName = url.lastPathComponent; error = nil
        } catch { self.error = "Could not read this file as UTF-8 text: \(error.localizedDescription)" }
    }
    private func review() {
        error = nil
        guard text.utf8.count <= 10_000_000 else { error = "Import is limited to 10 MB of text."; return }
        do { preview = try CSVImporter.parse(text) } catch { self.error = error.localizedDescription }
    }
    private func commit() {
        guard let preview else { return }
        do { importedCount = try store.importComputers(preview.computers, replaceExisting: replaceExisting); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
