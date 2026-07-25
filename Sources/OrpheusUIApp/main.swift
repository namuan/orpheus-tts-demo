import Cocoa
import SwiftUI
import MLX

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Orpheus TTS"
        window.contentView = NSHostingView(rootView: MainView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - App Bootstrap

// The terminal launch script ships a stub Metal library, not MLX's full kernel
// library. Xcode launches do not set this flag and therefore retain GPU support.
if ProcessInfo.processInfo.environment["ORPHEUS_USE_CPU"] == "1" {
    Device.setDefault(device: .cpu)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
