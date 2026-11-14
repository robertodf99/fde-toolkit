import AppKit

/// Menu-bar agent (no Dock icon): listens on the hook socket and shows each request as a
/// native macOS notification.
@main
enum HookMeUpMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
