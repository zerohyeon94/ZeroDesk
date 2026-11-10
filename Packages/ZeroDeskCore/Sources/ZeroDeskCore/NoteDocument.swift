import Foundation

/// 경로로 정하는 읽기 방식 (스펙 5).
public enum NoteLayout: Equatable, Sendable {
    case queue, daily, longRead

    public static func forPath(_ path: String) -> NoteLayout {
        if path == "Schedule/학습 대기열.md" { return .queue }
        if path.hasPrefix("Daily/") { return .daily }
        return .longRead
    }
}

/// `##` 절 하나. 머리 절(첫 `##` 앞)은 `title == ""`.
public struct NoteSection: Identifiable {
    public var id: Int
    public var title: String
    public var blocks: [Markup]
}

public struct NoteDocument {
    public var title: String?
    public var sections: [NoteSection]

    /// 앞머리 제거 → 위키 링크 바꾸기 → 파싱 → 최상위 `##`마다 절 나누기.
    /// 코드 블록 안 `#` 줄은 CodeBlock 안에 있으므로 제목이 되지 않는다.
    public static func parse(_ text: String) -> NoteDocument {
        let doc = Document(parsing: WikiLinks.rewrite(Frontmatter.strip(text)))
        var blocks = Array(doc.children)
        var title: String?
        if let h = blocks.first as? Heading, h.level == 1 {
            title = h.plainText
            blocks.removeFirst()
        }
        var sections = [NoteSection(id: 0, title: "", blocks: [])]
        for b in blocks {
            if let h = b as? Heading, h.level == 2 {
                sections.append(NoteSection(id: sections.count, title: h.plainText, blocks: []))
            } else {
                sections[sections.count - 1].blocks.append(b)
            }
        }
        return NoteDocument(title: title, sections: sections)
    }

    /// `##` 절 제목 또는 그 안 `###` 제목이 같은 절의 id.
    public func sectionIndex(forHeading heading: String) -> Int? {
        let h = heading.trimmingCharacters(in: .whitespaces)
        return sections.first { s in
            s.title == h || s.blocks.contains { ($0 as? Heading)?.plainText == h }
        }?.id
    }
}

extension Heading {
    public var plainText: String {
        children.compactMap { ($0 as? InlineMarkup)?.plainText }.joined().trimmingCharacters(in: .whitespaces)
    }
}
