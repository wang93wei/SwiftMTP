import Foundation

public extension MTPReader {
    /// 解码 MTP UCS-2 字符串。对应 Go encoding.go decodeStr。
    /// 线序:1 字节 sz(codepoint 数,含尾零) → sz 个小端 uint16 codepoint → 去尾零。
    mutating func readMTPString() throws -> String {
        let sz = Int(try readU8())
        if sz == 0 { return "" }
        var units = [UInt16](repeating: 0, count: sz)
        for i in 0..<sz { units[i] = try readU16() }
        // Go: if utfStr[w-1] == 0 { w-- } —— 最后一个 codepoint 若是 0(尾零)去掉
        if units.last == 0 { units.removeLast() }
        // UCS-2 → String(BMP;MTP 无 surrogate pair)
        return String(utf16CodeUnits: units, count: units.count)
    }
}
