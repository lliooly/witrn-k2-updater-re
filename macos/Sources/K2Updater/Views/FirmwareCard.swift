import SwiftUI
import UniformTypeIdentifiers

struct FirmwareCard: View {
    @ObservedObject var store: UpdaterStore
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("固件")
                    .font(.headline)
                Spacer()
                Button("选择本地固件") { FirmwarePicker.choose(store) }
                    .disabled(store.isBusy)
            }

            if let firmware = store.firmware {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(firmware.model) · \(firmware.version)")
                            .font(.title3)
                            .fontWeight(.medium)
                        Spacer()
                        Text("✓ 已验证")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }

                    HStack(spacing: 16) {
                        Text(firmware.date)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(firmware.sizeText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Text(store.firmwareURL?.lastPathComponent ?? "")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择或拖入 .k2 固件")
                        .font(.callout)
                    Text("会先检查型号、长度和校验值")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            guard !store.isBusy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { store.inspect(url) } }
            }
            return true
        }
    }
}
