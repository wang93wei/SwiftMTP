import Foundation

private let mtpUTC = TimeZone(identifier: "UTC")!

private func mtpDateFormatter(_ format: String) -> DateFormatter {
    let f = DateFormatter()
    f.dateFormat = format
    f.timeZone = mtpUTC
    f.calendar = Calendar(identifier: .gregorian)
    return f
}

public extension MTPReader {
    /// 解码 MTP 时间。对应 Go encoding.go decodeTime。
    /// 线序:readMTPString 得字符串 → 空则返回 nil(无时间);
    /// 三星尾点 trimRight(".");Jolla 尾 Z trimRight("Z");
    /// 主格式 "yyyyMMdd'T'HHmmss"(UTC);失败回退 Nokia "yyyyMMdd'T'HHmmssZZZZZ"。
    mutating func readMTPTime() throws -> Date? {
        let raw = try readMTPString()
        if raw.isEmpty { return nil }
        var s = raw
        // Go: strings.TrimRight(s, ".") 然后 TrimRight(s, "Z")
        while s.hasSuffix(".") { s.removeLast() }
        while s.hasSuffix("Z") { s.removeLast() }

        if let d = mtpDateFormatter("yyyyMMdd'T'HHmmss").date(from: s) { return d }
        if let d = mtpDateFormatter("yyyyMMdd'T'HHmmssZZZZZ").date(from: s) { return d }
        throw MTPDecodeError.invalidTime(raw)
    }
}
