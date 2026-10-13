import AppKit

/// Menu bar app: no Dock icon, no main window. `.accessory` plus LSUIElement in
/// Info.plist keep it out of the Dock and the app switcher.
///
/// The same binary also runs as the Claude Code hook (`Notch --hook`), which is
/// why that is checked before AppKit is started at all: the hook must be fast
/// and must never bring up a UI.
@main
struct NotchApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--hook") {
            HookCLI.run()
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
