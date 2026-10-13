import AppKit

/// Where the notch is and how big it is, on the screen we draw on.
struct NotchGeometry {
    let screen: NSScreen
    /// True when the screen really has a notch (auxiliary areas + safe area inset).
    let isRealNotch: Bool
    let notchSize: CGSize

    var frame: NSRect { screen.frame }
    var screenTop: CGFloat { screen.frame.maxY }
    var centerX: CGFloat { screen.frame.midX }
    var leftEdge: CGFloat { screen.frame.minX }
    var rightEdge: CGFloat { screen.frame.maxX }

    /// Notch rect in Cocoa screen coordinates (origin bottom-left).
    var notchRect: NSRect {
        NSRect(x: centerX - notchSize.width / 2,
               y: screenTop - notchSize.height,
               width: notchSize.width,
               height: notchSize.height)
    }
}

enum NotchLocator {
    /// Used on Macs without a notch: same footprint as a 14"/16" MacBook Pro.
    static let fakeNotchSize = CGSize(width: 200, height: 32)

    /// NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea are the reliable
    /// source: the notch is what is left over between them. safeAreaInsets.top
    /// gives its height.
    static func realNotchSize(for screen: NSScreen) -> CGSize? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = screen.frame.width - left.width - right.width
        let height = screen.safeAreaInsets.top
        // Sanity check: a notch is a wide, short, centred bar.
        guard width > 80, height > 8, width < screen.frame.width * 0.6 else { return nil }
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    static func geometry(for screen: NSScreen) -> NotchGeometry {
        if let size = realNotchSize(for: screen) {
            return NotchGeometry(screen: screen, isRealNotch: true, notchSize: size)
        }
        return NotchGeometry(screen: screen, isRealNotch: false, notchSize: fakeNotchSize)
    }

    /// The screen that has the notch, else the main screen.
    static func preferredScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { realNotchSize(for: $0) != nil }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func current() -> NotchGeometry? {
        guard let screen = preferredScreen() else { return nil }
        return geometry(for: screen)
    }
}
