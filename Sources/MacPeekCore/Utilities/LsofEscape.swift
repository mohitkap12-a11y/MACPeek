import Foundation

/// lsof's `-F` output escapes some bytes (spaces, control characters, non-ASCII) as `\xNN`.
public enum LsofEscape {
    public static func decode(_ value: String) -> String {
        guard value.contains("\\x") else { return value }
        var bytes: [UInt8] = []
        let utf8 = Array(value.utf8)
        var i = 0
        while i < utf8.count {
            if utf8[i] == UInt8(ascii: "\\"), i + 3 < utf8.count, utf8[i + 1] == UInt8(ascii: "x"),
               let byte = UInt8(String(decoding: utf8[(i + 2)...(i + 3)], as: UTF8.self), radix: 16) {
                bytes.append(byte)
                i += 4
            } else {
                bytes.append(utf8[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
