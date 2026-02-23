import Foundation

enum IDGenerator {
    static func inviteCode(length: Int = 8) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no O/0/I/1
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(chars.randomElement()!)
        }
        return result
    }
}
