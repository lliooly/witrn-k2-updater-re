import Foundation

struct DeviceInfo: Decodable, Identifiable, Hashable {
    let pathHex: String
    let productString: String?
    let manufacturerString: String?
    let serialNumber: String?
    let interfaceNumber: Int?
    var id: String { pathHex }
    var title: String { productString ?? "WITRN K2" }
    var detail: String { "序列号 \(serialNumber ?? "未知") · 接口 \(interfaceNumber ?? 0)" }
}

struct IdentityInfo: Decodable {
    let bootStrings: [String]
    let infoSha256: String
    let confirmedK2: Bool
    let currentVersion: String?
    let currentMarkerHex: String?
}

struct FirmwareInfo: Decodable {
    let model: String
    let version: String
    let date: String
    let appSize: Int
    let fileSha256: String
    let eraseSectors: Int
    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(appSize), countStyle: .file) }
}

enum StageTitle {
    static func text(_ stage: String) -> String {
        ["preflight": "准备", "validate": "检查固件", "handshake": "连接设备",
         "identify": "核对设备", "inspect-app": "读取当前版本", "probe-complete": "设备读取完成",
         "backup-read": "读取备份", "backup-verify": "再次读取并核对备份",
         "backup-recovery": "生成恢复文件", "backup-complete": "备份完成",
         "log-reset": "准备升级", "erase": "擦除应用区", "write": "写入固件",
         "verify": "读回校验", "commit": "提交固件", "exit": "结束升级", "complete": "升级完成",
         "resource-validate": "检查资源", "resource-backup-read": "读取原始资源备份",
         "resource-backup-verify": "再次读取并核对资源备份", "resource-backup-complete": "资源备份完成",
         "resource-erase": "擦除资源扇区", "resource-write": "写入资源", "resource-verify": "完整读回资源",
         "resource-exit": "结束资源写入", "resource-complete": "资源写入完成"][stage] ?? stage
    }
}
