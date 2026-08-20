import AppKit
import SwiftUI

@main
struct PullrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appStore = AppStore()

    var body: some Scene {
        Window("Pullr", id: "main") {
            RootView()
                .environmentObject(appStore)
                .preferredColorScheme(.dark)
                .frame(minWidth: 920, minHeight: 580)
                .onOpenURL { url in
                    appStore.addFromDeepLink(url)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand()
            }

            CommandMenu("Downloads") {
                Button("Add from Clipboard") {
                    appStore.addFromClipboard()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button(appStore.isQueueRunning ? "Stop Queue" : "Start Queue") {
                    appStore.startQueue()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Divider()

                Button("Grid View") {
                    appStore.queueViewMode = .grid
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("List View") {
                    appStore.queueViewMode = .list
                }
                .keyboardShortcut("2", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(isStandalone: true)
                .environmentObject(appStore)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
