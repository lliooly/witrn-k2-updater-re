import SwiftUI
import UniformTypeIdentifiers

struct FirmwareCard: View {
    @ObservedObject var store: UpdaterStore
    @State private var targeted = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("固件", systemImage: "doc.badge.arrow.up").font(.headline)
                    Spacer()
                    Button("选择固件…") { FirmwarePicker.choose(store) }.disabled(store.isBusy)
                }
                if let firmware = store.firmware {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(firmware.model) · \(firmware.version)").font(.title2).fontWeight(.semibold)
                        Text("\(firmware.date) · \(firmware.sizeText)").foregroundStyle(.secondary)
                        Spacer()
                        Label("检查通过", systemImage: "checkmark.shield").foregroundStyle(.green)
                    }
                    Text(store.firmwareURL?.lastPathComponent ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("选择或拖入 .k2 固件").font(.title3)
                    Text("会先检查型号、长度和校验值，再允许升级。").foregroundStyle(.secondary)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(targeted ? Color.accentColor : .clear, lineWidth: 2))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            guard !store.isBusy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { store.inspect(url) } }
            }
            return true
        }
    }
}
