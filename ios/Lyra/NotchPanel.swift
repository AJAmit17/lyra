import SwiftUI

/// A panel that grows out of the Dynamic Island: square against the screen edge, flaring at the
/// shoulders, rounded at the bottom. The same shape the Mac app hangs from the notch.
struct NotchShape: Shape {
    var topRadius: CGFloat = 12
    var bottomRadius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = min(bottomRadius, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                          control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                          control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                          control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Drops out of the island while Lyra is listening or working, and gets out of the way otherwise.
struct NotchPanel: View {
    let title: String
    let subtitle: String
    let level: Double
    let isOpen: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isOpen {
                VStack(spacing: 10) {
                    Wave(level: level).frame(height: 34).padding(.horizontal, 26)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.center)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2).multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 62)
                .padding(.bottom, 20)
                .padding(.horizontal, 26)
                .frame(maxWidth: .infinity)
                .background(NotchShape().fill(Color.black))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isOpen)
        .allowsHitTesting(false)
    }
}

/// A single travelling wave that swells with the microphone. Same idea as the Mac's pixel field.
private struct Wave: View {
    let level: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let swell = 3 + level * 14
                let dots = 90
                for index in 0..<dots {
                    let position = Double(index) / Double(dots - 1)
                    let phase = now * 2.4 - position * 8
                    let swayed = sin(phase) * 0.7 + sin(phase * 0.43 + 1.1) * 0.3
                    let taper = sin(position * .pi)
                    let x = position * size.width
                    let y = size.height / 2 + swayed * swell * (0.25 + 0.75 * taper)
                    let opacity = (0.25 + 0.6 * (0.5 + 0.5 * swayed)) * (0.3 + 0.7 * taper)
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)),
                                 with: .color(.white.opacity(opacity)))
                }
            }
        }
    }
}
