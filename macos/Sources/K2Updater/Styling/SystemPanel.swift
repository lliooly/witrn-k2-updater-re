import AppKit
import SwiftUI

/// Shared geometry for the window's panels.
enum LayoutMetrics {
    static let radiusPanel: CGFloat = 12
    static let pagePadding: CGFloat = 20
    /// The default width used to align the collapsed toggle with the open sidebar.
    static let navigationSidebarIdealWidth: CGFloat = 190
    static let navigationSidebarHeaderInset: CGFloat = 12
    static let navigationSidebarToggleSize: CGFloat = 19
    /// Additional horizontal offset for the toggle shown while the sidebar is collapsed.
    static let navigationSidebarCollapsedToggleTrailingOffset: CGFloat = 33
    /// Matches the central title bar's vertical center when the sidebar is open.
    static let navigationSidebarHeaderHeight: CGFloat = 60
    /// The strip the window traffic lights sit in, at the top of the window.
    static let titlebarHeight: CGFloat = 38
    /// The traffic-light group edge plus a small gap for the collapsed toolbar.
    static let trafficLightTrailing: CGFloat = 80
    /// The visual icon stays compact, while the clickable area remains easy to hit.
    static let toolbarActionHitSize: CGFloat = 40
    static let toolbarActionSpacing: CGFloat = 8
    static let toolbarActionPressedSpacing: CGFloat = 2
    /// Between the idle and pressed gaps, so fusion only happens while pressed.
    static let toolbarGlassBlendSpacing: CGFloat = 6
    /// Shared symbol size for the two trailing toolbar actions.
    static let toolbarActionIconSize: CGFloat = 18
    static let connectionSidebarWidth: CGFloat = 260
    static let connectionSidebarAnimation: Animation = .easeInOut(duration: 0.24)
}

/// Shared system glass surface for custom panels that sit beside native views.
struct SystemGlassSurface: ViewModifier {
    let active: Bool

    init(active: Bool = true) {
        self.active = active
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if !active {
            content
        } else if #available(macOS 26.0, *) {
            content.background {
                NativeGlassBackground(interactive: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        } else {
            content.background(.regularMaterial)
        }
    }
}

/// AppKit's native Liquid Glass surface, used for full-width system-like bars.
/// SwiftUI's `glassEffect` is still used for compact custom controls below.
@available(macOS 26.0, *)
private struct NativeGlassBackground: NSViewRepresentable {
    let interactive: Bool

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = 0
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = interactive
        }
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.style = .regular
        view.cornerRadius = 0
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = interactive
        }
    }
}

/// An independent glass surface for each toolbar action.
struct SystemGlassToolbarButtonSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
                .glassEffectTransition(.materialize)
        } else {
            content.background(.regularMaterial, in: Circle())
        }
    }
}

/// Observes the control's real press state without transforming its label.
struct ToolbarGlassPressObserver: ButtonStyle {
    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed, perform: onPressChanged)
            .onDisappear { onPressChanged(false) }
    }
}

extension View {
    /// The stock content background: a system colour with a corner radius.
    /// No tint, no border, no shadow.
    func systemPanel(radius: CGFloat = LayoutMetrics.radiusPanel) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}
