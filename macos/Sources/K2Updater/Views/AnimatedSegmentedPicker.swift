import SwiftUI

/// Shared segmented control with a sliding selection background.
struct AnimatedSegmentedPicker<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(value: Selection, title: String)]

    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.body.weight(selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "selection", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selection)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onMoveCommand { direction in
            guard isEnabled, let index = options.firstIndex(where: { $0.value == selection }) else { return }
            switch direction {
            case .left: selection = options[max(0, index - 1)].value
            case .right: selection = options[min(options.count - 1, index + 1)].value
            default: break
            }
        }
    }
}
