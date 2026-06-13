import Foundation

/// P3 三星补丁:接口串含 MTP/CDC/ACM 之一即视为 MTP(对应 Go mtp.go:196)。
/// 大小写敏感(对齐 Go strings.Contains,勿用 localizedCaseInsensitiveContains)。
public func interfaceStringLooksLikeMTP(_ s: String) -> Bool {
    s.contains("MTP") || s.contains("CDC") || s.contains("ACM")
}

/// P4 兜底:无接口串时,MTPExtension 含 microsoft/WindowsPhone 或 fujifilm.co.jp(对应 Go mtp.go:179-180)。
public func mtpExtensionFallback(_ ext: String) -> Bool {
    ext.contains("microsoft/WindowsPhone") || ext.contains("fujifilm.co.jp")
}

/// 设备 ID 正则匹配(对应 Go select.go:103:pattern=="" || regex.find(id)!="")。
public func deviceMatchesPattern(_ id: String, pattern: String) throws -> Bool {
    if pattern.isEmpty { return true }
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(id.startIndex..., in: id)
    return regex.firstMatch(in: id, range: range) != nil
}
