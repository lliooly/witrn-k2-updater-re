import SwiftUI

/// All pages share one horizontal offset, so arrival and departure cannot disagree.
struct FirmwareSlideDeck<Page: View>: View {
    let step: Int
    @Binding var isMoving: Bool
    let page: (Int) -> Page
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: Double
    @State private var heights: [Int: CGFloat] = [:]
    @State private var resetTask: Task<Void, Never>?
    private let duration = 0.28

    init(step: Int, isMoving: Binding<Bool>, @ViewBuilder page: @escaping (Int) -> Page) {
        self.step = step
        _isMoving = isMoving
        self.page = page
        _position = State(initialValue: Double(step))
    }

    var body: some View {
        GeometryReader { viewport in
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<5) { slot in
                    // The fifth slot is the next task's first page. After arrival,
                    // rebase invisibly to slot zero for its remaining steps.
                    let index = slot % 4
                    page(index)
                        .frame(width: viewport.size.width, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: FirmwarePageHeights.self,
                                                       value: [slot: geometry.size.height])
                            }
                        }
                        .allowsHitTesting(slot == Int(position) && !isMoving)
                        .accessibilityHidden(slot != Int(position))
                }
            }
            .offset(x: -CGFloat(position) * viewport.size.width)
        }
            .frame(height: heights[Int(position) % 4] ?? 1)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onPreferenceChange(FirmwarePageHeights.self) { values in
                // Slot zero owns the first-page height; its duplicate has the same content.
                heights = values.filter { $0.key < 4 }
            }
            .onChange(of: step) { next in
                resetTask?.cancel()
                let nextPosition = FirmwareSlideRoute.destination(from: position, to: next)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: duration)) {
                    position = nextPosition
                }
                if reduceMotion {
                    position = nextPosition == 4 ? 0 : nextPosition
                    isMoving = false
                    return
                }
                isMoving = true
                resetTask = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) }
                    catch { return }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if nextPosition == 4 { position = 0 }
                        isMoving = false
                    }
                }
            }
            .onDisappear { resetTask?.cancel(); isMoving = false }
    }
}

enum FirmwareSlideRoute {
    static func destination(from position: Double, to step: Int) -> Double {
        position == 3 && step == 0 ? 4 : Double(step)
    }
}

private struct FirmwarePageHeights: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
