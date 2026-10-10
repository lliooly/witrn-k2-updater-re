import SwiftUI

/// Show/hide control for the left navigation sidebar.
///
/// The system-supplied toolbar item is removed (see `ContentView`), so this is
/// the only sidebar control: it sits in the sidebar's own header while the
/// sidebar is open, and in the top bar's leading edge while it is collapsed.
struct NavigationSidebarToggle: View {
    @Binding var expanded: Bool
    var size: CGFloat = 19

    private var description: String { expanded ? "收起功能导航栏" : "展开功能导航栏" }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            button
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            button
                .padding(5)
                .background(.regularMaterial, in: Circle())
                .buttonStyle(.plain)
        }
    }

    private var button: some View {
        Button {
            expanded.toggle()
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.system(size: size, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .help(description)
        .accessibilityLabel(description)
    }
}
