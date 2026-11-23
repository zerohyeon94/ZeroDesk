import Foundation

/// 글자에 붙는 형광펜 하나. 화면 좌표가 아니라 "어느 절의 어떤 글"로 저장하므로
/// 글자 크기·화면 폭이 바뀌어도, iPhone에서 봐도 같은 문장에 붙는다.
/// 위치는 칠한 글(`quote`)과 그 앞뒤 글(`prefix`, `suffix`)로 찾는다 (같은 글이 여러 번 나와도 구분).
public struct Highlight: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// 절 열쇠 (`NoteDocument.inkKeys`).
    public var section: String
    public var quote: String
    public var prefix: String
    public var suffix: String
    public var color: HighlightColor
    /// 형광펜에 단 메모 (손글씨·글). 없으면 `nil`. 메모가 없는 예전 파일도 그대로 읽힌다.
    public var memo: HighlightMemo?

    public init(id: UUID = UUID(), section: String, quote: String, prefix: String, suffix: String, color: HighlightColor,
                memo: HighlightMemo? = nil) {
        self.id = id
        self.section = section
        self.quote = quote
        self.prefix = prefix
        self.suffix = suffix
        self.color = color
        self.memo = memo
    }

    /// 앞뒤로 함께 적어 두는 글 길이 (UTF-16).
    public static let contextLength = 24

    /// 문단 글에서 `range`(UTF-16)를 칠한 형광펜을 만든다. 앞뒤 공백은 뺀다. 칠할 글이 없으면 `nil`.
    public static func make(section: String, paragraph: String, range: NSRange, color: HighlightColor) -> Highlight? {
        let ns = paragraph as NSString
        var r = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        let space = CharacterSet.whitespacesAndNewlines
        while r.length > 0, let u = UnicodeScalar(ns.character(at: r.location)), space.contains(u) { r.location += 1; r.length -= 1 }
        while r.length > 0, let u = UnicodeScalar(ns.character(at: NSMaxRange(r) - 1)), space.contains(u) { r.length -= 1 }
        guard r.length > 0 else { return nil }
        let r2 = ns.rangeOfComposedCharacterSequences(for: r)
        let pStart = max(0, r2.location - contextLength)
        let sEnd = min(ns.length, NSMaxRange(r2) + contextLength)
        return Highlight(section: section, quote: ns.substring(with: r2),
                         prefix: ns.substring(with: NSRange(location: pStart, length: r2.location - pStart)),
                         suffix: ns.substring(with: NSRange(location: NSMaxRange(r2), length: sEnd - NSMaxRange(r2))),
                         color: color)
    }

    /// 이 문단 글에서 형광펜 자리(UTF-16)를 찾는다. 칠한 글이 여러 번 나오면 앞뒤 글이 가장 많이 맞는 곳.
    /// 앞뒤 글이 전혀 맞지 않으면, 칠한 글이 길 때(8자 이상)만 받아들인다 (짧은 글이 엉뚱한 곳에 붙지 않게).
    public func locate(in paragraph: String) -> NSRange? { match(in: paragraph)?.range }

    /// 자리와 앞뒤 글이 맞은 글자 수.
    public func match(in paragraph: String) -> (range: NSRange, score: Int)? {
        let ns = paragraph as NSString
        guard !quote.isEmpty else { return nil }
        var best: (range: NSRange, score: Int)?
        var from = 0
        while from < ns.length {
            let r = ns.range(of: quote, options: [], range: NSRange(location: from, length: ns.length - from))
            guard r.location != NSNotFound else { break }
            let before = ns.substring(to: r.location)
            let after = ns.substring(from: NSMaxRange(r))
            let score = Self.commonSuffix(prefix, before) + Self.commonPrefix(suffix, after)
            if best == nil || score > best!.score { best = (r, score) }
            from = r.location + max(r.length, 1)
        }
        guard let best else { return nil }
        // 공백 하나쯤 맞는 것은 우연이므로 2자 이상 맞아야 앞뒤 글이 맞았다고 본다.
        let contextFits = best.score >= 2 || (prefix.isEmpty && suffix.isEmpty)
        return contextFits || (quote as NSString).length >= 8 ? best : nil
    }

    /// 절 안의 문단들 중 형광펜마다 가장 잘 맞는 문단 하나를 고른다 (같은 글이 다른 문단에도 있을 때 한 곳에만 칠하게).
    public static func resolve(_ highlights: [Highlight], paragraphs: [String]) -> [UUID: (paragraph: Int, range: NSRange)] {
        var out: [UUID: (paragraph: Int, range: NSRange)] = [:]
        for h in highlights {
            var best: (paragraph: Int, range: NSRange, score: Int)?
            for (i, p) in paragraphs.enumerated() {
                if let m = h.match(in: p), best == nil || m.score > best!.score { best = (i, m.range, m.score) }
            }
            if let best { out[h.id] = (best.paragraph, best.range) }
        }
        return out
    }

    static func commonSuffix(_ a: String, _ b: String) -> Int {
        zip(a.utf16.reversed(), b.utf16.reversed()).prefix { $0 == $1 }.count
    }

    static func commonPrefix(_ a: String, _ b: String) -> Int {
        zip(a.utf16, b.utf16).prefix { $0 == $1 }.count
    }
}

/// 형광펜 메모: 키보드로 쓴 글과 Pencil 손글씨(`PKDrawing.dataRepresentation()`)를 함께 둘 수 있다.
public struct HighlightMemo: Codable, Equatable, Hashable, Sendable {
    public var text: String
    public var drawing: Data?

    public init(text: String = "", drawing: Data? = nil) {
        self.text = text
        self.drawing = drawing
    }

    /// 글도 손글씨도 없으면 빈 메모 (저장하지 않는다).
    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (drawing?.isEmpty ?? true) }
}

public enum HighlightColor: String, Codable, CaseIterable, Sendable {
    case yellow, green, pink, blue

    public var label: String {
        switch self {
        case .yellow: "노랑"
        case .green: "초록"
        case .pink: "분홍"
        case .blue: "파랑"
        }
    }
}
