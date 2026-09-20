import SwiftUI

/// A panel that grows out of the Dynamic Island.
///
/// The island is not a notch: it is a free-floating pill inset from the top edge, so this starts
/// at exactly the pill's size and position and swells downwards from it. Arriving overshoots
/// slightly; leaving eases out without bouncing back. The content is held back a moment so the
/// shape leads the motion, and only opacity and scale move once the shape has settled.
struct IslandPanel: View {
    let title: String
    let subtitle: String
    let level: Double
    let isListening: Bool
    let isOpen: Bool

    /// iPhone 14 Pro and later. On phones without an island this reads as a floating card.
    private let pillWidth: CGFloat = 126
    private let pillHeight: CGFloat = 37.33
    private let topInset: CGFloat = 11

    private var expandedWidth: CGFloat { UIScreen.main.bounds.width - 24 }
    private var expandedHeight: CGFloat { subtitle.isEmpty ? 132 : 158 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: isOpen ? 44 : pillHeight / 2, style: .continuous)
                    .fill(Color.black)
                    .frame(width: isOpen ? expandedWidth : pillWidth,
                           height: isOpen ? expandedHeight : pillHeight)
                    .shadow(color: .black.opacity(isOpen ? 0.45 : 0), radius: 22, y: 10)

                content
                    .frame(width: expandedWidth - 40)
                    // Clear of the camera cutout, which lives in the pill itself.
                    .padding(.top, pillHeight + 14)
                    .opacity(isOpen ? 1 : 0)
                    .scaleEffect(isOpen ? 1 : 0.9, anchor: .top)
                    .animation(isOpen ? .easeOut(duration: 0.22).delay(0.08)
                                      : .easeIn(duration: 0.12), value: isOpen)
            }
            .padding(.top, topInset)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(isOpen ? .spring(response: 0.42, dampingFraction: 0.80)
                          : .smooth(duration: 0.30), value: isOpen)
    }

    private var content: some View {
        VStack(spacing: 10) {
            Wave(level: level, active: isListening).frame(height: 26)
            Text(title)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center)
                .contentTransition(.opacity)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        }
    }
}

/// One travelling wave, swelling with the microphone. Still when there is nothing to hear.
private struct Wave: View {
    let level: Double
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let swell = active ? 2.5 + level * 12 : 0.6
                let dots = 84
                for index in 0..<dots {
                    let position = Double(index) / Double(dots - 1)
                    let phase = now * 2.4 - position * 8
                    let swayed = sin(phase) * 0.7 + sin(phase * 0.43 + 1.1) * 0.3
                    let taper = sin(position * .pi)
                    let x = position * size.width
                    let y = size.height / 2 + swayed * swell * (0.25 + 0.75 * taper)
                    let opacity = (0.25 + 0.6 * (0.5 + 0.5 * swayed)) * (0.3 + 0.7 * taper)
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)),
                                 with: .color(.white.opacity(opacity)))
                }
            }
        }
    }
}
