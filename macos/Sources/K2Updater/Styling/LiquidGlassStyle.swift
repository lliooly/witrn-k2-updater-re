import SwiftUI

// MARK: - Liquid Glass Styling System
struct LiquidGlassStyle {
    // MARK: - Glass Background Modifiers
    static func glassBackground(_ opacity: Double = 0.85) -> some View {
        return AnyView(
            Color(nsColor: .controlBackgroundColor)
                .opacity(opacity)
                .background(.ultraThinMaterial)
                .blur(radius: 0.5)
        )
    }

    static func thinGlassBackground(_ opacity: Double = 0.75) -> some View {
        return AnyView(
            Color.white
                .opacity(0.3)
                .background(.thinMaterial)
        )
    }

    // MARK: - Card Styling
    static func glassCard<Content: View>(_ content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }

    static func glassCardCompact<Content: View>(_ content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.thinMaterial)
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 1)
    }

    // MARK: - Divider with Glass Effect
    static var glassDivider: some View {
        Divider()
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.05),
                        Color.black.opacity(0),
                        Color.black.opacity(0.05)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

// MARK: - View Extension for Liquid Glass Modifiers
extension View {
    func liquidGlassBackground(opacity: Double = 0.85) -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(opacity))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }

    func liquidGlassCompact(opacity: Double = 0.8) -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(opacity))
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.thinMaterial)
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 1)
    }

    func glassOverlay(opacity: Double = 0.85) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(opacity))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
}
