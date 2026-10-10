import SwiftUI

/// Shows the real on-disk trace without adding traffic to the device event pipe.
struct FirmwareLogConsole: View {
    let path: String?
    var active = true
    @StateObject private var tail = FirmwareLogTail()
    @State private var followsLatest = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("实时日志", systemImage: "terminal").font(.callout.weight(.medium))
                Text("UTC").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("跟随最新", isOn: $followsLatest).toggleStyle(.checkbox).font(.caption)
                    .disabled(path == nil)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(tail.lines) { line in
                            Text(line.text)
                                .foregroundStyle(line.isError ? Color.red : Color.green.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                }
                .frame(height: 220)
                .background(Color(red: 0.025, green: 0.04, blue: 0.035), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: tail.lines.last?.id) { _ in
                    if followsLatest { proxy.scrollTo("latest", anchor: .bottom) }
                }
                .onChange(of: followsLatest) { follows in
                    if follows { proxy.scrollTo("latest", anchor: .bottom) }
                }
            }
            Text("显示最近 300 条，完整记录可通过底部“日志”按钮打开。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: "\(path ?? "")|\(active)") {
            guard active else { return }
            tail.reset()
            guard let path else { return }
            while !Task.isCancelled {
                tail.read(path: path)
                do { try await Task.sleep(nanoseconds: 250_000_000) }
                catch { return }
            }
        }
    }
}

struct FirmwareLogLine: Identifiable {
    let id: Int
    let text: String
    let isError: Bool
}

/// Bounded incremental reads keep both memory and rendering independent of trace size.
@MainActor
final class FirmwareLogTail: ObservableObject {
    @Published private(set) var lines: [FirmwareLogLine] = []
    private var offset: UInt64 = 0
    private var partial = Data()
    private var nextID = 0
    private var reportedReadError = false

    func reset() {
        lines = []; offset = 0; partial = Data(); nextID = 0; reportedReadError = false
    }

    func read(path: String) {
        do {
            let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? file.close() }
            let size = try file.seekToEnd()
            if size < offset { reset() }
            // A busy transport can write faster than the UI refreshes. Keep its latest window.
            let limit: UInt64 = 256 * 1024
            let skipsOlder = size - offset > limit
            if skipsOlder { offset = size - limit; partial = Data() }
            try file.seek(toOffset: offset)
            let data = try file.read(upToCount: Int(limit)) ?? Data()
            guard !data.isEmpty else { return }
            offset += UInt64(data.count)
            partial.append(data)
            if skipsOlder {
                if let newline = partial.firstIndex(of: 10) { partial.removeSubrange(...newline) }
                else { partial = Data(); return }
            }
            var added: [FirmwareLogLine] = []
            while let newline = partial.firstIndex(of: 10) {
                let record = Data(partial[..<newline])
                partial.removeSubrange(...newline)
                guard !record.isEmpty else { continue }
                added.append(Self.line(record, id: nextID)); nextID += 1
            }
            if !added.isEmpty { lines = Array((lines + added).suffix(300)) }
            reportedReadError = false
        } catch {
            guard !reportedReadError else { return }
            reportedReadError = true
            lines = Array((lines + [FirmwareLogLine(id: nextID,
                text: "[LOG] 暂时无法读取日志：\(error.localizedDescription)", isError: true)]).suffix(300))
            nextID += 1
        }
    }

    private static func line(_ data: Data, id: Int) -> FirmwareLogLine {
        guard let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FirmwareLogLine(id: id, text: String(decoding: data, as: UTF8.self), isError: false)
        }
        let kind = fields["kind"] as? String ?? "log"
        let time = fields["time"] as? String ?? ""
        let stamp = time.count >= 23 ? String(time.dropFirst(11).prefix(12)) : time
        var details = fields
        details.removeValue(forKey: "time"); details.removeValue(forKey: "kind")
        let payload = (try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        return FirmwareLogLine(id: id, text: "[\(stamp)] \(kind.uppercased()) \(payload)",
                               isError: kind == "error" || kind == "interrupted")
    }
}
