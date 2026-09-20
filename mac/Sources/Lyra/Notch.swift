import AppKit
import SwiftUI

/// Geometry of the built-in display's notch, and the panel that hangs from it.
/// Main-thread only: every member touches AppKit.
enum Notch {
    /// The notch display if there is one, otherwise the main display's top edge.
    static var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The physical notch, or a stand-in strip of the same shape on Macs without one.
    static func size() -> CGSize {
        let screen = Notch.screen
        let height = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return CGSize(width: 190, height: height)
        }
        return CGSize(width: max(screen.frame.width - left.width - right.width, 100), height: height)
    }

    /// Hangs the window from the top centre of the notch display, flush with the screen edge.
    static func place(_ window: NSWindow, size: CGSize, animate: Bool = false) {
        let screen = Notch.screen
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(),
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        window.setFrame(frame, display: true, animate: animate)
    }
}

/// A rectangle that flares out of the screen edge and rounds off at the bottom: the notch, grown.
/// The body is inset by `topRadius` on each side so the flare stays inside the frame.
struct NotchShape: Shape {
    var topRadius: CGFloat = 9
    var bottomRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = min(bottomRadius, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
