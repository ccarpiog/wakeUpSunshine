import SwiftUI
import AppKit

@main
struct WakeUpSunshineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    var body: some Scene {
        Window("Wake Up Sunshine", id: "main") {
            ContentView(store: store)
                .tint(Sunshine.accent)
                .frame(minWidth: 920, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 760)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Computer…") { NotificationCenter.default.post(name: .addComputer, object: nil) }.keyboardShortcut("n")
                Button("Import Computers…") { NotificationCenter.default.post(name: .importComputers, object: nil) }.keyboardShortcut("i")
            }
            CommandMenu("Computers") {
                Button("Refresh Status") { Task { await store.refresh() } }.keyboardShortcut("r")
                Button("Wake Selected Computers") { Task { await store.wake(store.selectedComputers) } }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(store.selection.isEmpty || store.isWaking)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let addComputer = Notification.Name("WakeUpSunshine.addComputer")
    static let importComputers = Notification.Name("WakeUpSunshine.importComputers")
}

enum Sunshine {
    static let accent = Color(red: 0.88, green: 0.39, blue: 0.13)
    static let gold = Color(red: 0.97, green: 0.65, blue: 0.22)
    static let subtle = Color.primary.opacity(0.045)
}

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.8).foregroundStyle(.secondary)
    }
}

struct StatusBadge: View {
    var status: DeviceStatus
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text(status.title).font(.system(size: 11, weight: .medium))
        }.foregroundStyle(status.color)
    }
}
