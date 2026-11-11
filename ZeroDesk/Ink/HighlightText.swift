import SwiftUI
import UIKit
import ZeroDeskCore

/// 노트 읽기 화면이 문단마다 넘겨 주는 형광펜 정보. 없으면(다른 화면) 문단을 SwiftUI `Text`로 그린다.
struct HighlightContext {
    /// 절 열쇠 (`NoteDocument.inkKeys`).
    var section: String
    /// 이 절의 형광펜.
    var highlights: [Highlight]
    /// 형광펜마다 고른 문단 글과 자리 (`Highlight.resolve`). 이 문단 글과 같은 것만 칠한다.
    var placed: [UUID: (text: String, range: NSRange)]
    /// 형광펜 모드: Pencil로 글자를 그어 칠하고, 칠한 곳을 누르면 지운다.
    var marking: Bool
    var color: HighlightColor
    var add: (Highlight) -> Void
    var remove: (UUID) -> Void
}

extension EnvironmentValues {
    @Entry var highlightContext: HighlightContext? = nil
}

extension HighlightColor {
    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor.systemYellow.withAlphaComponent(0.4)
        case .green: UIColor.systemGreen.withAlphaComponent(0.3)
        case .pink: UIColor.systemPink.withAlphaComponent(0.28)
        case .blue: UIColor.systemBlue.withAlphaComponent(0.25)
        }
    }

    var swatch: Color {
        switch self {
        case .yellow: .yellow
        case .green: .green
        case .pink: .pink
        case .blue: .blue
        }
    }
}

/// 형광펜을 칠할 수 있는 문단. 글자 위치를 알아야 해서 SwiftUI `Text` 대신 TextKit(`UITextView`)으로 그린다.
/// 모양은 `Text`와 같게 맞춘다: 본문 글꼴, 줄 간격 6, 굵게·기울임·코드·취소선·링크.
struct HighlightText: UIViewRepresentable {
    let text: AttributedString
    let context: HighlightContext

    private var plain: String { String(text.characters) }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context ctx: Context) -> UITextView {
        // 점 → 글자 위치를 정확히 재려고 TextKit 1(layoutManager)을 쓴다.
        let v = UITextView(usingTextLayoutManager: false)
        v.isEditable = false
        v.isSelectable = true
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.linkTextAttributes = [:]  // 링크 색은 글에 직접 칠한다 (없는 링크는 회색)
        v.delegate = ctx.coordinator
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        #if targetEnvironment(simulator)
        let touchTypes: [NSNumber] = [UITouch.TouchType.pencil.rawValue as NSNumber, UITouch.TouchType.direct.rawValue as NSNumber]
        #else
        let touchTypes: [NSNumber] = [UITouch.TouchType.pencil.rawValue as NSNumber]  // 손가락은 스크롤
        #endif
        let pan = UIPanGestureRecognizer(target: ctx.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = ctx.coordinator
        pan.allowedTouchTypes = touchTypes
        pan.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target: ctx.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.allowedTouchTypes = touchTypes
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(tap)
        ctx.coordinator.pan = pan
        ctx.coordinator.tap = tap
        return v
    }

    func updateUIView(_ v: UITextView, context ctx: Context) {
        let c = ctx.coordinator
        c.parent = self
        c.openURL = ctx.environment.openURL
        c.font = UIFont.preferredFont(forTextStyle: .body,
                                      compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(ctx.environment.dynamicTypeSize)))
        c.tint = v.tintColor
        let plain = plain
        c.located = context.highlights.compactMap { h in
            guard let p = context.placed[h.id], p.text == plain else { return nil }
            return (range: p.range, highlight: h)
        }
        c.pan?.isEnabled = context.marking
        c.tap?.isEnabled = context.marking
        c.render(v)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let w = proposal.width, w.isFinite, w > 0 else { return nil }
        let s = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: w, height: ceil(s.height))
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: HighlightText?
        var openURL: OpenURLAction?
        var font = UIFont.preferredFont(forTextStyle: .body)
        var tint: UIColor = .tintColor
        var located: [(range: NSRange, highlight: Highlight)] = []
        weak var pan: UIPanGestureRecognizer?
        weak var tap: UITapGestureRecognizer?
        /// Pencil로 긋는 중인 범위 (손을 떼면 저장).
        private var live: NSRange?
        private var start = 0
        /// 처음 닿은 자리. 끌기는 조금 움직인 뒤에야 시작되므로 닿는 순간을 따로 적어 둔다.
        private var touchDown: CGPoint?

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if g === pan { touchDown = touch.location(in: g.view) }
            return true
        }
        private var shown: NSAttributedString?

        func render(_ v: UITextView) {
            guard let parent else { return }
            let s = Self.build(parent.text, font: font, tint: tint, located: located, live: live.map { ($0, parent.context.color) })
            guard shown == nil || !s.isEqual(to: shown!) else { return }
            shown = s
            v.attributedText = s
            v.invalidateIntrinsicContentSize()
        }

        static func build(_ text: AttributedString, font body: UIFont, tint: UIColor,
                          located: [(range: NSRange, highlight: Highlight)], live: (NSRange, HighlightColor)?) -> NSAttributedString {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 6
            let out = NSMutableAttributedString()
            for run in text.runs {
                let piece = String(text[run.range].characters)
                let intent = run.inlinePresentationIntent ?? []
                var font = intent.contains(.code) ? UIFont.monospacedSystemFont(ofSize: body.pointSize * 0.94, weight: .regular) : body
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if !traits.isEmpty, let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits)) {
                    font = UIFont(descriptor: d, size: 0)
                }
                var attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para, .foregroundColor: UIColor.label]
                if let url = run.link {
                    attrs[.link] = url
                    attrs[.foregroundColor] = tint
                }
                if let c = run.swiftUI.foregroundColor { attrs[.foregroundColor] = UIColor(c) }
                if run.swiftUI.strikethroughStyle != nil { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                out.append(NSAttributedString(string: piece, attributes: attrs))
            }
            let all = NSRange(location: 0, length: out.length)
            for (r, h) in located { out.addAttribute(.backgroundColor, value: h.color.uiColor, range: NSIntersectionRange(r, all)) }
            if let (r, c) = live { out.addAttribute(.backgroundColor, value: c.uiColor, range: NSIntersectionRange(r, all)) }
            return out
        }

        /// 화면의 점 아래 글자 사이 위치(0…글자 수). 글자의 오른쪽 절반이면 다음 위치.
        private func index(_ v: UITextView, _ p: CGPoint) -> Int {
            let lm = v.layoutManager
            let tc = v.textContainer
            let q = CGPoint(x: p.x - v.textContainerInset.left, y: p.y - v.textContainerInset.top)
            var fraction: CGFloat = 0
            let i = lm.characterIndex(for: q, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)
            return min(v.textStorage.length, i + (fraction > 0.5 ? 1 : 0))
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view as? UITextView else { return }
            let i = index(v, g.location(in: v))
            switch g.state {
            case .began:
                start = touchDown.map { index(v, $0) } ?? i
                live = NSRange(location: min(start, i), length: abs(i - start))
            case .changed:
                live = NSRange(location: min(start, i), length: abs(i - start))
            case .ended:
                if let r = live, let parent, let h = Highlight.make(section: parent.context.section, paragraph: v.attributedText.string,
                                                                    range: r, color: parent.context.color) {
                    parent.context.add(h)
                }
                live = nil
            default:
                live = nil
            }
            render(v)
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? UITextView else { return }
            let i = index(v, g.location(in: v))
            // 누른 글자를 덮는 형광펜 중 가장 위(나중에 칠한 것)를 지운다.
            if let hit = located.last(where: { NSLocationInRange(i, $0.range) || NSLocationInRange(i - 1, $0.range) }) {
                parent?.context.remove(hit.highlight.id)
            }
        }

        // 손가락으로 글을 고르면 메뉴에 "형광펜" / "형광펜 지우기"를 넣는다.
        func textView(_ v: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let parent, range.length > 0 else { return nil }
            var actions: [UIMenuElement] = [UIAction(title: "형광펜", image: UIImage(systemName: "highlighter")) { [weak v] _ in
                if let h = Highlight.make(section: parent.context.section, paragraph: v?.attributedText.string ?? "",
                                          range: range, color: parent.context.color) {
                    parent.context.add(h)
                }
                v?.selectedRange = NSRange(location: 0, length: 0)
            }]
            let overlapping = located.filter { NSIntersectionRange($0.range, range).length > 0 }
            if !overlapping.isEmpty {
                actions.append(UIAction(title: "형광펜 지우기", attributes: .destructive) { [weak v] _ in
                    overlapping.forEach { parent.context.remove($0.highlight.id) }
                    v?.selectedRange = NSRange(location: 0, length: 0)
                })
            }
            return UIMenu(children: actions + suggestedActions)
        }

        // 링크는 앱의 링크 처리(칸 이동·없는 링크 알림)로 연다.
        func textView(_ v: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case let .link(url) = textItem.content else { return defaultAction }
            return UIAction { [weak self] _ in self?.openURL?(url) }
        }
    }
}
