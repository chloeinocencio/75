import SwiftUI

/// Three soft chartreuse fields drifting behind the app.
///
/// This is the iOS twin of the web build's `.aura`. Its brightness is the day's completion,
/// so the screen literally warms up as the checklist fills — it means something rather than
/// being decoration. `bloom` flashes it to full once when the day closes.
///
/// Motion uses long `repeatForever` animations rather than a `TimelineView`, so the drift is
/// interpolated by Core Animation instead of re-rendering SwiftUI 30 times a second — it
/// costs almost nothing in battery. Reduce Motion freezes it in place.
struct AuraBackground: View {
    var glow: Double
    var bloom: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    private var restingOpacity: Double {
        let g = min(max(glow, 0), 1)
        return colorScheme == .dark ? 0.16 + g * 0.44 : 0.30 + g * 0.70
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) * 1.15

            ZStack {
                field(Theme.lime, alpha: 0.46, size: s)
                    .position(x: geo.size.width * 0.08, y: geo.size.height * 0.04)
                    .offset(x: drifting ? s * 0.16 : 0, y: drifting ? s * 0.12 : 0)
                    .scaleEffect(drifting ? 1.14 : 1)
                    .animation(drift(46), value: drifting)

                field(Theme.lime, alpha: 0.30, size: s)
                    .position(x: geo.size.width * 0.95, y: geo.size.height * 0.98)
                    .offset(x: drifting ? -s * 0.14 : 0, y: drifting ? -s * 0.16 : 0)
                    .scaleEffect(drifting ? 1 : 1.08)
                    .animation(drift(58), value: drifting)

                field(Theme.warmGlow, alpha: 0.26, size: s)
                    .position(x: geo.size.width * 1.05, y: geo.size.height * 0.52)
                    .offset(x: drifting ? -s * 0.18 : 0, y: drifting ? s * 0.14 : 0)
                    .scaleEffect(drifting ? 1.2 : 1)
                    .animation(drift(52), value: drifting)
            }
        }
        .opacity(bloom ? 1 : restingOpacity)
        .animation(.easeOut(duration: bloom ? 0.5 : 1.4), value: bloom)
        .animation(.easeInOut(duration: 1.4), value: glow)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            drifting = true
        }
    }

    private func drift(_ seconds: Double) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: seconds).repeatForever(autoreverses: true)
    }

    private func field(_ color: Color, alpha: Double, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(alpha), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.36
                )
            )
            .frame(width: size, height: size)
    }
}
