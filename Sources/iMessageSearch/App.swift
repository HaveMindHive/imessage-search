import SwiftUI
import AppKit

// Plain SwiftUI WindowGroup apps don't reopen a window when you click the Dock
// icon after closing the last one — clicking does nothing visible, which looks
// exactly like a crash. This makes reopen actually work, without needing
// SwiftUI's openWindow environment plumbing threaded through the delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Must be a stored property — a window created as a local variable with no
    // other strong reference gets deallocated (and silently closes) the moment
    // this method returns, before it ever has a chance to render.
    private var reopenedWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = NSHostingView(rootView: ContentView())
        window.makeKeyAndOrderFront(nil)
        reopenedWindow = window
        return true
    }
}

@main
struct IMessageSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Open Full Disk Access Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                Button("Open Contacts Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!)
                }
            }
        }
    }
}
