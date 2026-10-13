import Foundation

/// Pointer intent is separate from click capture. The invisible approach area
/// never intercepts clicks intended for the menu bar or another application.
struct PointerRegion {
    static let approachSide: CGFloat = 12
    static let approachBelow: CGFloat = 10
    static let exitMargin: CGFloat = 8

    static func activation(notch: CGRect) -> CGRect {
        CGRect(x: notch.minX - approachSide,
               y: notch.minY - approachBelow,
               width: notch.width + approachSide * 2,
               height: notch.height + approachBelow + 1)
    }

    static func contains(_ point: CGPoint, notch: CGRect, island: CGRect, open: Bool) -> Bool {
        if activation(notch: notch).contains(point) { return true }
        return open && island.insetBy(dx: -exitMargin, dy: -exitMargin).contains(point)
    }
}
