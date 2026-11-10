import SwiftUI
import UIKit

/// 코드 블록 글꼴. 한글이 고정폭 글꼴에 없어 대체 글꼴로 그려지면 폭이 칸에 맞지 않아 텍스트 그림이 어긋난다.
/// 그래서 글자마다 자간(kern)을 더해 넓은 글자(한글·한자·전각)는 정확히 2칸, 나머지는 1칸이 되게 한다.
enum MonoGrid {
    static var font: UIFont { UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular) }

    @MainActor private static var widths: [String: CGFloat] = [:]

    @MainActor static func text(_ code: String, font: UIFont = font) -> AttributedString {
        let cell = width("M", font)
        var out = AttributedString()
        for ch in code {
            var a = AttributedString(String(ch))
            if ch != "\n" {
                let target = cell * (isWide(ch) ? 2 : 1)
                let w = width(String(ch), font)
                if abs(target - w) > 0.01 { a.kern = target - w }
            }
            out += a
        }
        out.font = Font(font)
        return out
    }

    @MainActor static func width(_ s: String, _ font: UIFont) -> CGFloat {
        let key = "\(font.pointSize)|\(s)"
        if let w = widths[key] { return w }
        let w = (s as NSString).size(withAttributes: [.font: font]).width
        widths[key] = w
        return w
    }

    /// 동아시아 넓은 글자(Wide/Fullwidth) 범위.
    static func isWide(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x1100...0x115F).contains(v) || (0x2E80...0x303E).contains(v) || (0x3041...0x33FF).contains(v)
            || (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xA960...0xA97F).contains(v)
            || (0xAC00...0xD7A3).contains(v) || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE4F).contains(v)
            || (0xFF00...0xFF60).contains(v) || (0xFFE0...0xFFE6).contains(v)
    }
}
