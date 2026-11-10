import SwiftUI
import ZeroDeskCore

/// 인라인 마크다운 → AttributedString. 문단 안 한 번 바꾼 줄(SoftBreak)도 줄을 바꾼다 (스펙 5.3).
/// `index`를 주면 볼트에 없는 위키 링크를 회색으로 보여 준다 (스펙 6).
func inlineText(_ markup: Markup, index: VaultIndex? = nil) -> AttributedString {
    markup.children.reduce(into: AttributedString()) { $0 += inline($1, index) }
}

private func inline(_ m: Markup, _ index: VaultIndex?) -> AttributedString {
    switch m {
    case let t as Markdown.Text:
        return AttributedString(t.string)
    case is SoftBreak, is LineBreak:
        return AttributedString("\n")
    case let c as InlineCode:
        var a = AttributedString(c.code)
        a.inlinePresentationIntent = .code
        return a
    case is Strong:
        return adding(.stronglyEmphasized, to: inlineText(m, index: index))
    case is Emphasis:
        return adding(.emphasized, to: inlineText(m, index: index))
    case is Strikethrough:
        var a = inlineText(m, index: index)
        a.strikethroughStyle = .single
        return a
    case let l as Markdown.Link:
        var a = inlineText(l, index: index)
        guard let d = l.destination, let url = URL(string: d) else { return a }
        a.link = url
        if let index, let p = AppLink.parse(url), !p.target.isEmpty, index.resolve(p.target) == nil {
            a.foregroundColor = .secondary
        }
        return a
    case let i as Markdown.Image:
        return AttributedString(i.plainText.isEmpty ? "[그림]" : i.plainText)
    case let h as InlineHTML:
        return AttributedString(h.rawHTML)
    default:
        return AttributedString((m as? InlineMarkup)?.plainText ?? "")
    }
}

private func adding(_ intent: InlinePresentationIntent, to s: AttributedString) -> AttributedString {
    var a = s
    for run in a.runs { a[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent) }
    return a
}
