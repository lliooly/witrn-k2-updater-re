import SwiftUI
import UniformTypeIdentifiers

struct FirmwareCard: View {
    @ObservedObject var store: UpdaterStore
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("固件", systemImage: "doc.badge.gearshape").font(.title3.weight(.semibold))
                Spacer()
                Button { FirmwarePicker.choose(store) } label: {
                    Label("选择固件", systemImage: "folder")
                }.disabled(store.isBusy)
            }
            if let firmware = store.firmware {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(firmware.model) · \(firmware.version)").font(.title2.weight(.semibold))
                        Spacer()
                        Label("检查通过", systemImage: "checkmark.shield.fill").foregroundStyle(.green).font(.callout)
                    }
                    HStack(spacing: 12) {
                        Label(firmware.date, systemImage: "calendar").font(.callout).foregroundStyle(.secondary)
                        Label(firmware.sizeText, systemImage: "doc").font(.callout).foregroundStyle(.secondary)
                    }
                    Text(store.firmwareURL?.lastPathComponent ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择或拖入 .k2 固件").font(.title3)
                    Text("会先检查型号、长度和校验值，再允许升级").foregroundStyle(.secondary).font(.callout)
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(targeted ? Color.accentColor : .clear, lineWidth: 2))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                guard !store.isBusy, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { store.inspect(url) } }
                }
                return true
            }
    }
}
