import Foundation
import Combine

struct OfficialFirmwareRelease: Equatable {
    let version: String
    let downloadURL: URL
}

struct OfficialFirmwareService {
    static let pageURL = URL(string: "https://www.witrn.com/?p=2105")!

    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && ["www.witrn.com", "witrn.com"].contains(url.host?.lowercased() ?? "")
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "OfficialFirmware", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func userMessage(_ error: Error) -> String {
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain {
            switch failure.code {
            case NSURLErrorTimedOut: return "官网连接超时，请重试或选择本地固件。"
            case NSURLErrorCancelled: return "检查已取消，可重新检查。"
            default: return "无法连接官网，请检查网络或选择本地固件。"
            }
        }
        if failure.domain == NSCocoaErrorDomain { return "无法保存文件，请检查磁盘空间和目录权限。" }
        return error.localizedDescription
    }

    static func latest(in html: String) throws -> OfficialFirmwareRelease {
        let anchors = try NSRegularExpression(pattern: #"<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, options: .caseInsensitive)
        let names = try NSRegularExpression(pattern: #"^K2_V([0-9]+\.[0-9]+)\.zip$"#, options: .caseInsensitive)
        let tags = try NSRegularExpression(pattern: "<[^>]+>")
        var candidates: [OfficialFirmwareRelease] = []
        for match in anchors.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html) else { continue }
            let label = String(html[labelRange])
            let text = tags.stringByReplacingMatches(in: label, range: NSRange(label.startIndex..., in: label), withTemplate: "")
            guard text.uppercased().contains("K2"), text.contains("固件包"),
                  let url = URL(string: String(html[hrefRange]).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: pageURL)?.absoluteURL,
                  allowed(url), url.path.hasPrefix("/witrn/K2/") else { continue }
            let filename = url.lastPathComponent
            guard let versionMatch = names.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
                  let versionRange = Range(versionMatch.range(at: 1), in: filename) else { continue }
            candidates.append(OfficialFirmwareRelease(version: String(filename[versionRange]), downloadURL: url))
        }
        guard let latest = candidates.max(by: {
            $0.version.compare($1.version, options: .numeric) == .orderedAscending
        }) else { throw failure("未识别到官网 K2 固件，请选择本地固件或打开官网。") }
        return latest
    }

    static func fetch(_ url: URL, limit: Int) async throws -> Data {
        guard allowed(url) else { throw failure("下载地址不属于 WITRN 官网。") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("WITRN-K2-Updater", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let finalURL = response.url, allowed(finalURL) else {
            throw failure("官网连接失败，请重试或选择本地固件。")
        }
        guard response.expectedContentLength <= limit else { throw failure("官网文件过大。") }
        var result = Data()
        for try await byte in bytes {
            guard result.count < limit else { throw failure("官网文件过大。") }
            result.append(byte)
        }
        return result
    }
}

@MainActor
final class OfficialFirmwareStore: ObservableObject {
    @Published private(set) var release: OfficialFirmwareRelease?
    @Published private(set) var checking = false
    @Published private(set) var downloading = false
    @Published private(set) var errorMessage: String?
    private var attempted = false

    func checkIfNeeded() async {
        guard !attempted else { return }
        await check()
    }

    func check() async {
        guard !checking, !downloading else { return }
        attempted = true; checking = true; errorMessage = nil
        defer { checking = false }
        do {
            let data = try await OfficialFirmwareService.fetch(OfficialFirmwareService.pageURL, limit: 2 * 1024 * 1024)
            guard let html = String(data: data, encoding: .utf8) else {
                throw OfficialFirmwareService.failure("官网页面编码无法识别。")
            }
            release = try OfficialFirmwareService.latest(in: html)
        } catch {
            release = nil
            errorMessage = "检查官网失败：\(OfficialFirmwareService.userMessage(error))"
        }
    }

    func download(to directory: URL, use: (URL, String) -> Void) async {
        guard !checking, !downloading, let release else { return }
        downloading = true; errorMessage = nil
        defer { downloading = false }
        do {
            let data = try await OfficialFirmwareService.fetch(release.downloadURL, limit: 8 * 1024 * 1024)
            let folder = directory.appendingPathComponent("Downloaded Firmware", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let archive = folder.appendingPathComponent("\(UUID().uuidString).zip")
            try data.write(to: archive, options: .atomic)
            use(archive, release.version)
        } catch {
            errorMessage = "下载失败：\(OfficialFirmwareService.userMessage(error))"
        }
    }
}
