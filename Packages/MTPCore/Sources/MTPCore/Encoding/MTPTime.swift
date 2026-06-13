import Foundation

private let mtpUTC = TimeZone(identifier: "UTC")!

// DateFormatter 是 Foundation 重对象,static 缓存避免每次 readMTPTime 重复构造
// (批量列目录场景:数百文件 × CaptureDate/ModificationDate 会高频调用)。
private let mtpTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd'T'HHmmss"
    f.timeZone = mtpUTC
    f.calendar = Calendar(identifier: .gregorian)
    return f
}()

private let mtpTimeNumTZFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd'T'HHmmssZZZZZ"
    f.timeZone = mtpUTC
    f.calendar = Calendar(identifier: .gregorian)
    return f
}()

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

        if let d = mtpTimeFormatter.date(from: s) { return d }
        if let d = mtpTimeNumTZFormatter.date(from: s) { return d }
        throw MTPDecodeError.invalidTime(raw)
    }
}
