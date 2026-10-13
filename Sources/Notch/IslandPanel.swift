import AppKit
import SwiftUI

/// Borderless panel that never becomes key and never activates the app.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit's default keeps windows out of the menu bar strip. The island has
    /// to sit at the very top of the screen, so no clamping.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Panel content view. It owns the tracking area that reports pointer movement
/// over the notch — tracking lives on the panel, never on the menu bar — and
/// relay clicks that land on the island.
final class IslandContainerView: NSView {
    var onPointerMove: ((NSPoint) -> Void)?
    var onPointerExit: (() -> Void)?

    private var area: NSTrackingArea?

    /// First click is delivered even though the panel is not key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let new = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(new)
        area = new
    }

    override func mouseEntered(with event: NSEvent) { report(event) }
    override func mouseMoved(with event: NSEvent) { report(event) }
    override func mouseExited(with event: NSEvent) { onPointerExit?() }

    private func report(_ event: NSEvent) {
        onPointerMove?(convert(event.locationInWindow, from: nil))
    }
}

/// NSHostingView that accepts the first mouse click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
