import SwiftUI

/// The island outline.
///
/// As in the mockups: one rounded card flush with the top of the screen, with
/// the black band over the physical notch drawn inside it. The closed pill uses
/// square top corners and is exactly notch height, so pill and notch read as a
/// single shape; the open island rounds all four corners.
///
/// Coordinate space is SwiftUI's (origin top-left, y down).
struct IslandShape: Shape {
    /// Width of the band over the notch (kept for the closed states, where the
    /// pill may grow wider than the notch).
    var topWidth: CGFloat
    /// Full width.
    var width: CGFloat
    /// Height of the black band over the physical notch.
    var topBand: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(width, topWidth), .init(topRadius, bottomRadius)) }
        set {
            width = newValue.first.first
            topWidth = newValue.first.second
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = max(width, 1)
        let h = max(rect.height, 1)
        let tr = max(0, min(topRadius, w / 2, h / 2))
        let br = max(0, min(bottomRadius, w / 2, h / 2))

        var p = Path()
        p.move(to: CGPoint(x: tr, y: 0))
        p.addLine(to: CGPoint(x: w - tr, y: 0))
        if tr > 0 {
            p.addRelativeArc(center: CGPoint(x: w - tr, y: tr), radius: tr,
                             startAngle: .degrees(-90), delta: .degrees(90))
        }
        p.addLine(to: CGPoint(x: w, y: h - br))
        if br > 0 {
            p.addRelativeArc(center: CGPoint(x: w - br, y: h - br), radius: br,
                             startAngle: .degrees(0), delta: .degrees(90))
        }
        p.addLine(to: CGPoint(x: br, y: h))
        if br > 0 {
            p.addRelativeArc(center: CGPoint(x: br, y: h - br), radius: br,
                             startAngle: .degrees(90), delta: .degrees(90))
        }
        p.addLine(to: CGPoint(x: 0, y: tr))
        if tr > 0 {
            p.addRelativeArc(center: CGPoint(x: tr, y: tr), radius: tr,
                             startAngle: .degrees(180), delta: .degrees(90))
        }
        p.closeSubpath()
        return p
    }
}

/// Rectangle with rounded bottom corners — matches the real notch silhouette so
/// the black band lines up with the hardware cutout.
struct NotchBandShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(bottomRadius, rect.width / 2, rect.height))
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        if r > 0 {
            p.addRelativeArc(center: CGPoint(x: rect.width - r, y: rect.height - r),
                             radius: r, startAngle: .degrees(0), delta: .degrees(90))
        }
        p.addLine(to: CGPoint(x: r, y: rect.height))
        if r > 0 {
            p.addRelativeArc(center: CGPoint(x: r, y: rect.height - r),
                             radius: r, startAngle: .degrees(90), delta: .degrees(90))
        }
        p.addLine(to: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}
