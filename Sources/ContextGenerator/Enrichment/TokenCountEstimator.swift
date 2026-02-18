import Foundation

enum TokenCountEstimator {
    private static let latinCharactersPerToken = 3.0

    static func estimate(for text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }
        var cjkScalars = 0
        var nonCJKScalars = 0
        for scalar in text.unicodeScalars {
            if scalar.isCJKLike {
                cjkScalars += 1
            } else {
                nonCJKScalars += 1
            }
        }
        return cjkScalars + Int(ceil(Double(nonCJKScalars) / latinCharactersPerToken))
    }
}

private extension UnicodeScalar {
    var isCJKLike: Bool {
        switch value {
        case 0x2E80 ... 0x2FD5,
             0x2FF0 ... 0x2FFF,
             0x3040 ... 0x309F,
             0x30A0 ... 0x30FF,
             0x3100 ... 0x312F,
             0x3130 ... 0x318F,
             0x31A0 ... 0x31BF,
             0x31C0 ... 0x31EF,
             0x3400 ... 0x4DBF,
             0x4E00 ... 0x9FFF,
             0xAC00 ... 0xD7AF,
             0xF900 ... 0xFAFF,
             0xFF66 ... 0xFF9D:
            return true
        default:
            return false
        }
    }
}
