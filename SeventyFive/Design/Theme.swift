import SwiftUI
import UIKit

/// The 75 palette, shared with the web build: warm cream, soft chartreuse, near-black ink.
///
/// Chartreuse is a *fill* that carries ink. As text on cream it is only 1.2:1, so anything
/// that must be read in the accent colour uses `accentText`, which is ink in light mode and
/// chartreuse in dark mode — the same rule `app.css` follows with `--accent-text`.
enum Theme {
    static let bg = Color(light: 0xF5F0EA, dark: 0x14130E)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1E1C16)
    static let surface2 = Color(light: 0xE5DED6, dark: 0x2A2720)
    static let ink = Color(light: 0x0A0A0C, dark: 0xF0EBE3)
    static let dim = Color(light: 0x5E584F, dark: 0xA49C8F)
    static let line = Color(light: 0xE3DCD2, dark: 0x333028)

    static let lime = Color(hex: 0xDAE644)
    static let limeInk = Color(light: 0x0A0A0C, dark: 0x14130E)
    static let limeSoft = Color(light: 0xEDF3A8, dark: 0x3A3D1E)
    static let accentText = Color(light: 0x0A0A0C, dark: 0xDAE644)
    static let warmGlow = Color(hex: 0xFFD68C)

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A colour that resolves per appearance, so one token works in light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Surfaces

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }

    /// The app's page background: cream (or warm near-black) with the living aura behind.
    func themedBackground(glow: Double = 0, bloom: Bool = false) -> some View {
        background {
            ZStack {
                Theme.bg
                AuraBackground(glow: glow, bloom: bloom)
            }
            .ignoresSafeArea()
        }
    }
}

/// Primary call to action: chartreuse fill carrying ink, with a hairline edge in light mode
/// so the button still has an outline against the cream page.
struct LimeButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(Theme.limeInk)
            .padding(.vertical, compact ? 9 : 15)
            .padding(.horizontal, compact ? 14 : 20)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(Theme.lime, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(Color(light: 0x0A0A0C, dark: 0xDAE644).opacity(0.16), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Secondary action: quiet beige pill.
struct QuietButtonStyle: ButtonStyle {
    var compact = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(Theme.ink)
            .padding(.vertical, compact ? 9 : 15)
            .padding(.horizontal, compact ? 14 : 20)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Small uppercase label above a section, like the web build's card headings.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
