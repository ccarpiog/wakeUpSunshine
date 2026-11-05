import SwiftUI
import WakeCore

struct ComputerEditor: View {
    @ObservedObject var store: AppStore
    var computer: Computer?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ip = ""
    @State private var mac = ""
    @State private var group = "General"
    @State private var broadcast = "255.255.255.255"
    @State private var wakePort = "9"
    @State private var probePort = "22"
    @State private var advanced = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 13) {
                Image(systemName: "desktopcomputer").font(.system(size: 28)).foregroundStyle(Sunshine.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(computer == nil ? "Add a computer" : "Edit computer").font(.title2.bold())
                    Text("A name, an address, and a little sunshine.").foregroundStyle(.secondary).font(.caption)
                }
            }
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Studio PC"))
                    TextField("IP address", text: $ip, prompt: Text("192.168.1.42"))
                    TextField("MAC address", text: $mac, prompt: Text("AA:BB:CC:DD:EE:FF"))
                    TextField("Group", text: $group, prompt: Text("General"))
                }
                DisclosureGroup("Network settings", isExpanded: $advanced) {
                    TextField("Broadcast address", text: $broadcast)
                    TextField("Wake port (UDP)", text: $wakePort)
                    TextField("Status port (TCP)", text: $probePort)
                    Text("Use a service that is normally listening: SSH 22, RDP 3389, SMB 445, or Sunshine 47990. If that service is closed, the computer may appear unreachable even while awake.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.formStyle(.grouped).frame(height: advanced ? 340 : 230)
            if let error { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("Saved locally on this Mac.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(computer == nil ? "Add computer" : "Save changes", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 510)
        .onAppear {
            if let computer {
                name = computer.name; ip = computer.ipAddress; mac = computer.macAddress; group = computer.group
                broadcast = computer.broadcastAddress; wakePort = String(computer.wakePort); probePort = String(computer.probePort)
            }
        }
    }
    private func save() {
        guard let wake = UInt16(wakePort), wake > 0, let probe = UInt16(probePort), probe > 0 else { error = "Ports must be numbers from 1 to 65535."; return }
        do {
            var value = Computer(name: name, ipAddress: ip, macAddress: mac)
            if let computer { value.id = computer.id }
            value.group = group; value.broadcastAddress = broadcast; value.wakePort = wake; value.probePort = probe
            try store.saveComputer(value)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct SetupHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("A good morning starts here", systemImage: "sun.max.fill").font(.title2.bold()).foregroundStyle(Sunshine.accent)
            helpStep("1", "Enable Wake-on-LAN", "On each computer, enable Wake-on-LAN in BIOS/UEFI and in its network adapter settings. Use a wired Ethernet connection; waking over Wi-Fi is often unsupported.")
            helpStep("2", "Add your computers", "Enter a friendly name, IPv4 address, and Ethernet MAC address. Import a CSV file or paste rows copied from a spreadsheet to add many at once.")
            helpStep("3", "Check your network", "The default broadcast is 255.255.255.255 on UDP port 9. For another subnet, set a directed broadcast address in Network settings. Routers and VPNs may block broadcasts.")
            helpStep("4", "Wake and verify", "Select computers with the checkboxes and choose Wake selected. “Packet sent” only confirms sending. Status checks connect to a configurable TCP port; a blocked or closed port can look unreachable even on an awake computer.")
            Divider()
            Text("Computer records stay on this Mac. Wake Up Sunshine has no account, cloud service, tracking, or remote shutdown feature.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Got it") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 560)
    }
    private func helpStep(_ number: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number).font(.system(size: 13, weight: .bold)).foregroundStyle(Sunshine.accent).frame(width: 28, height: 28).background(Sunshine.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(body).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
