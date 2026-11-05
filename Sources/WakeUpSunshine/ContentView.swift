import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WakeCore

struct ContentView: View {
    @ObservedObject var store: AppStore
    @State private var showingImport = false
    @State private var showingEditor = false
    @State private var editingComputer: Computer?
    @State private var deletion: Set<UUID> = []
    @State private var showingDelete = false
    @State private var showingHelp = false
    @State private var showingAllActivity = false

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 275, idealWidth: 300, maxWidth: 370)
            detail.frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Check whether each computer's probe port responds (⌘R)")
                    .disabled(store.isRefreshing || store.computers.isEmpty)
                Divider()
                Button { showingImport = true } label: { Label("Import", systemImage: "square.and.arrow.down") }.help("Import computers from a file or clipboard (⌘I)")
                Button(action: export) { Label("Export", systemImage: "square.and.arrow.up") }.disabled(store.computers.isEmpty)
                Button { editingComputer = nil; showingEditor = true } label: { Label("Add Computer", systemImage: "plus") }.help("Add a computer (⌘N)")
                Button { showingHelp = true } label: { Label("Setup Help", systemImage: "questionmark.circle") }
            }
        }
        .sheet(isPresented: $showingImport) { ImportView(store: store) }
        .sheet(isPresented: $showingEditor) { ComputerEditor(store: store, computer: editingComputer) }
        .sheet(isPresented: $showingHelp) { SetupHelpView() }
        .alert("Remove \(deletion.count) computer\(deletion.count == 1 ? "" : "s")?", isPresented: $showingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                do { try store.deleteComputers(ids: deletion) } catch { store.errorMessage = error.localizedDescription }
            }
        } message: { Text("This removes saved entries from this Mac. It does not change or shut down the computers.") }
        .alert("Something needs attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .addComputer)) { _ in editingComputer = nil; showingEditor = true }
        .onReceive(NotificationCenter.default.publisher(for: .importComputers)) { _ in showingImport = true }
        .task {
            await store.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                await store.refresh()
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill").font(.system(size: 28)).foregroundStyle(Sunshine.accent.gradient)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wake Up Sunshine").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("A little energy. Everywhere.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 20).padding(.top, 23).padding(.bottom, 23)
            if ProcessInfo.processInfo.arguments.contains("--demo") {
                Label("Demo · no network packets sent", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Sunshine.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Sunshine.accent.opacity(0.08), in: Capsule()).padding(.bottom, 14)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search computers", text: $store.searchText).textFieldStyle(.plain)
                if !store.searchText.isEmpty { Button { store.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain) }
            }.padding(9).background(Sunshine.subtle, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 16)
            HStack {
                Picker("Group", selection: $store.selectedGroup) {
                    Text("All computers").tag(Optional<String>.none)
                    ForEach(store.groups, id: \.self) { Text($0).tag(Optional($0)) }
                }.labelsHidden().pickerStyle(.menu)
                Spacer()
                Text("\(store.filteredComputers.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 10)
            Divider().padding(.horizontal, 16)
            if store.filteredComputers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: store.computers.isEmpty ? "desktopcomputer" : "magnifyingglass").font(.title).foregroundStyle(.tertiary)
                    Text(store.computers.isEmpty ? "Your computers will appear here" : "No matching computers")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(store.filteredComputers) { computer in
                            ComputerRow(computer: computer, status: store.statuses[computer.id] ?? .unknown,
                                        isFocused: store.focusedID == computer.id,
                                        isSelected: store.selection.contains(computer.id),
                                        focus: { store.focusedID = computer.id },
                                        toggle: { if store.selection.contains(computer.id) { store.selection.remove(computer.id) } else { store.selection.insert(computer.id) } },
                                        canMoveUp: store.canMoveComputer(id: computer.id, direction: -1),
                                        canMoveDown: store.canMoveComputer(id: computer.id, direction: 1),
                                        moveUp: { moveComputer(computer.id, direction: -1) },
                                        moveDown: { moveComputer(computer.id, direction: 1) })
                            .contextMenu {
                                Button("Wake Computer") { Task { await store.wake([computer]) } }.disabled(store.isWaking)
                                Button("Edit…") { editingComputer = computer; showingEditor = true }
                                Divider()
                                Button("Move Up") { moveComputer(computer.id, direction: -1) }
                                    .disabled(!store.canMoveComputer(id: computer.id, direction: -1))
                                Button("Move Down") { moveComputer(computer.id, direction: 1) }
                                    .disabled(!store.canMoveComputer(id: computer.id, direction: 1))
                                Divider()
                                Button("Remove…", role: .destructive) { deletion = [computer.id]; showingDelete = true }
                            }
                        }
                    }.padding(10)
                }
            }
            Divider()
            VStack(spacing: 12) {
                HStack {
                    Button("Select all") { store.selection = Set(store.computers.map(\.id)) }
                        .buttonStyle(.plain).disabled(store.computers.isEmpty)
                        .help("Select every saved computer, including computers hidden by search or group filters")
                    Spacer()
                    Button("Clear") { store.selection.removeAll() }.buttonStyle(.plain).disabled(store.selection.isEmpty)
                }.font(.caption).foregroundStyle(.secondary)
                if !store.searchText.isEmpty || store.selectedGroup != nil {
                    let hiddenCount = store.selection.subtracting(store.filteredComputers.map(\.id)).count
                    if hiddenCount > 0 {
                        Text("\(hiddenCount) selected outside this view").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { Task { await store.wake(store.selectedComputers) } } label: {
                    HStack {
                        Image(systemName: "sun.max.fill")
                        Text(store.isWaking ? "Sending wake packets…" : "Wake selected (\(store.selection.count))")
                    }.font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).disabled(store.selection.isEmpty || store.isWaking)
                HStack(spacing: 5) {
                    Image(systemName: "lock.shield").font(.system(size: 10))
                    Text("Stored on this Mac · No account needed").font(.system(size: 10))
                }.foregroundStyle(.tertiary)
            }.padding(16)
        }.background(.regularMaterial)
    }

    private func moveComputer(_ id: UUID, direction: Int) {
        do { try store.moveComputer(id: id, direction: direction) }
        catch { store.errorMessage = error.localizedDescription }
    }

    @ViewBuilder private var detail: some View {
        if store.computers.isEmpty {
            welcome
        } else if store.selection.count > 1 {
            batchDetail
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let computer = store.selection.count == 1 ? store.selectedComputers.first : store.focusedComputer {
                        ComputerDetail(computer: computer, status: store.statuses[computer.id] ?? .unknown, isWaking: store.isWaking,
                                       wake: { Task { await store.wake([computer]) } },
                                       edit: { editingComputer = computer; showingEditor = true },
                                       remove: { deletion = [computer.id]; showingDelete = true })
                    } else {
                        overview
                    }
                    activityView
                }.padding(32).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Sunshine.gold.opacity(0.1)).frame(width: 170, height: 170)
                Circle().fill(Sunshine.gold.opacity(0.12)).frame(width: 125, height: 125)
                Image(systemName: "sun.max.fill").font(.system(size: 64, weight: .light)).foregroundStyle(Sunshine.accent.gradient)
            }
            VStack(spacing: 11) {
                Eyebrow(text: "GOOD MORNING, COMPUTERS")
                Text("Wake one. Or everyone.").font(.system(size: 32, weight: .semibold, design: .rounded))
                Text("Bring your computers together, then wake them\nwith a single click. Your network, ready when you are.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            }
            HStack(spacing: 12) {
                Button { showingImport = true } label: { Label("Import computers", systemImage: "square.and.arrow.down").padding(.horizontal, 8).padding(.vertical, 5) }.buttonStyle(.borderedProminent)
                Button { editingComputer = nil; showingEditor = true } label: { Label("Add one computer", systemImage: "plus").padding(.vertical, 5) }.buttonStyle(.bordered)
            }
            HStack(spacing: 20) {
                Label("CSV & spreadsheet paste", systemImage: "tablecells")
                Label("Batch wake", systemImage: "square.stack.3d.up")
                Label("Local & private", systemImage: "lock")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 14)
            Button("First time using Wake-on-LAN? Setup guide") { showingHelp = true }.buttonStyle(.link).font(.caption).padding(.top, 12)
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Eyebrow(text: "YOUR NETWORK")
            Text("Ready for a brighter start.").font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Choose a computer to see its connection details, or select several to wake them together.").foregroundStyle(.secondary)
            Button { Task { await store.wake(store.filteredComputers) } } label: {
                Label("Wake all visible (\(store.filteredComputers.count))", systemImage: "sun.max.fill")
            }.buttonStyle(.borderedProminent).disabled(store.filteredComputers.isEmpty || store.isWaking)
        }.padding(.vertical, 30)
    }

    private var batchDetail: some View {
        let selected = store.selectedComputers
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "TOGETHER IS BETTER")
                    Text("\(selected.count) computers selected").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("One click. A whole network of possibilities.").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 38)).foregroundStyle(Sunshine.accent)
            }
            Button { Task { await store.wake(selected) } } label: {
                Label(store.isWaking ? "Sending wake packets…" : "Wake \(selected.count) computers", systemImage: "sun.max.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent).disabled(store.isWaking)
            Text("Each computer receives a Wake-on-LAN packet. A sent packet is not a confirmation that the computer is online.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Clear selection") { store.selection.removeAll() }.buttonStyle(.link)
                Spacer()
                Button("Remove selected…", role: .destructive) { deletion = store.selection; showingDelete = true }.buttonStyle(.borderless)
            }.font(.caption)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(selected) { computer in
                        HStack {
                            Image(systemName: "desktopcomputer").foregroundStyle(Sunshine.accent).frame(width: 25)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(computer.name).fontWeight(.medium)
                                Text(computer.ipAddress).font(.caption.monospaced()).foregroundStyle(.secondary)
                                if let status = store.statuses[computer.id], case .failed(let reason) = status {
                                    Text(reason).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                                }
                            }
                            Spacer()
                            StatusBadge(status: store.statuses[computer.id] ?? .unknown)
                        }.padding(14).background(Sunshine.subtle, in: RoundedRectangle(cornerRadius: 10))
                    }
                    activityView.padding(.top, 20)
                }
            }
        }.padding(32).frame(maxWidth: 900).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var activityView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack {
                Eyebrow(text: "RECENT ACTIVITY")
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.small); Text("Checking status").font(.caption).foregroundStyle(.secondary) }
                if store.activity.count > 12 {
                    Button(showingAllActivity ? "Show recent" : "Show all (\(store.activity.count))") { showingAllActivity.toggle() }
                        .buttonStyle(.link).font(.caption)
                }
            }
            if store.activity.isEmpty {
                HStack(spacing: 10) { Image(systemName: "clock").foregroundStyle(.tertiary); Text("Wake results and status checks will appear here.").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10)
            } else {
                ForEach(Array(store.activity.prefix(showingAllActivity ? 300 : 12))) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isError ? "exclamationmark.circle" : "bolt.circle").foregroundStyle(item.isError ? .red : Sunshine.accent)
                        VStack(alignment: .leading, spacing: 3) { Text(item.computerName).font(.system(size: 12, weight: .medium)); Text(item.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        Spacer()
                        Text(item.date, style: .time).font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Wake Up Sunshine Computers.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportCSV().write(to: url, atomically: true, encoding: .utf8) }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private struct ComputerRow: View {
    var computer: Computer
    var status: DeviceStatus
    var isFocused: Bool
    var isSelected: Bool
    var focus: () -> Void
    var toggle: () -> Void
    var canMoveUp: Bool
    var canMoveDown: Bool
    var moveUp: () -> Void
    var moveDown: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) { Image(systemName: isSelected ? "checkmark.square.fill" : "square").font(.system(size: 15)).foregroundStyle(isSelected ? Sunshine.accent : Color.secondary.opacity(0.5)) }.buttonStyle(.plain).help("Select \(computer.name) for batch wake").accessibilityLabel("Select \(computer.name)")
            Button(action: focus) {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer").font(.system(size: 19)).foregroundStyle(Sunshine.accent).frame(width: 38, height: 38).background(Sunshine.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(computer.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        HStack(spacing: 5) { Circle().fill(status.color).frame(width: 5, height: 5); Text(computer.ipAddress).font(.system(size: 10).monospaced()).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            VStack(spacing: 2) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up").frame(width: 22, height: 17).contentShape(Rectangle())
                }.disabled(!canMoveUp).help("Move up in the list").accessibilityLabel("Move \(computer.name) up")
                Button(action: moveDown) {
                    Image(systemName: "chevron.down").frame(width: 22, height: 17).contentShape(Rectangle())
                }.disabled(!canMoveDown).help("Move down in the list").accessibilityLabel("Move \(computer.name) down")
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).buttonStyle(.plain)
        }.padding(.horizontal, 10).padding(.vertical, 10)
            .background(isFocused ? Sunshine.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct ComputerDetail: View {
    var computer: Computer
    var status: DeviceStatus
    var isWaking: Bool
    var wake: () -> Void
    var edit: () -> Void
    var remove: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Eyebrow(text: computer.group); Text(computer.name).font(.system(size: 28, weight: .semibold, design: .rounded)).textSelection(.enabled) }
                Spacer()
                Button(action: edit) { Label("Edit", systemImage: "slider.horizontal.3") }.buttonStyle(.bordered)
            }
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(status.color.opacity(0.065)).frame(width: 150, height: 150)
                    Circle().strokeBorder(status.color.opacity(0.4), lineWidth: 2).frame(width: 120, height: 120)
                    Image(systemName: status.symbol).font(.system(size: 48, weight: .light)).foregroundStyle(status.color)
                }
                Text(status.title).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(status.color)
                Text("Status checks use TCP port \(String(computer.probePort))").font(.caption).foregroundStyle(.secondary)
                if case .failed(let reason) = status {
                    Label(reason, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 8).padding(.bottom, 4)
            Button(action: wake) { Label(isWaking ? "Sending wake packets…" : "Wake computer", systemImage: "sun.max.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.borderedProminent).disabled(isWaking)
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "CONNECTION")
                VStack(spacing: 0) {
                    connectionRow("IP address", computer.ipAddress)
                    Divider().padding(.horizontal, 16)
                    connectionRow("MAC address", computer.macAddress)
                    Divider().padding(.horizontal, 16)
                    connectionRow("Broadcast", "\(computer.broadcastAddress):\(computer.wakePort)")
                    Divider().padding(.horizontal, 16)
                    connectionRow("Probe port", String(computer.probePort))
                }.background(Sunshine.subtle, in: RoundedRectangle(cornerRadius: 12))
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                    Text("Enable Wake-on-LAN on this computer and connect it by Ethernet. An unreachable probe port does not always mean the computer is asleep.")
                }.font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
            HStack { Button("Remove computer…", role: .destructive, action: remove).buttonStyle(.borderless).font(.caption); Spacer() }
        }
    }
    private func connectionRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).font(.system(size: 12).monospaced()).textSelection(.enabled) }.padding(.horizontal, 16).padding(.vertical, 12)
    }
}
