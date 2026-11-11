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
    /// 형광펜 지우기 (메모가 달려 있으면 읽기 화면이 먼저 묻는다).
    var remove: (UUID) -> Void
    /// 형광펜 메모 창 열기.
    var openMemo: (UUID) -> Void
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

    func makeUIView(context ctx: Context) -> InkTextView {
        let v = InkTextView.make()
        v.isEditable = false
        v.isSelectable = true
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.linkTextAttributes = [:]  // 링크 색은 글에 직접 칠한다 (없는 링크는 회색)
        v.delegate = ctx.coordinator
        v.clipsToBounds = false  // 메모 표시가 문단 위쪽 여백으로 살짝 나가도 잘리지 않게
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
        // 읽기 모드: 칠한 곳이나 메모 표시를 누르면 메모 창을 연다 (손가락·Pencil 모두). 다른 곳은 링크·글 고르기가 받는다.
        let open = UITapGestureRecognizer(target: ctx.coordinator, action: #selector(Coordinator.openTap(_:)))
        open.delegate = ctx.coordinator
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(open)
        ctx.coordinator.pan = pan
        ctx.coordinator.tap = tap
        ctx.coordinator.open = open
        return v
    }

    func updateUIView(_ v: InkTextView, context ctx: Context) {
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
        c.open?.isEnabled = !context.marking
        c.render(v)
        v.bands = c.located.map { ($0.range, $0.highlight.color.uiColor) }
        v.memos = c.located.filter { $0.highlight.memo != nil }.map(\.range)
        v.bandFont = c.font
        // 형광펜 모드에서는 Pencil로 화면이 스크롤되지 않게 한다 (칠하는 동안 글이 밀려 엉뚱한 곳이 칠해짐).
        let marking = context.marking
        DispatchQueue.main.async { [weak v] in v?.pencilScrolls(!marking) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: InkTextView, context: Context) -> CGSize? {
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
        weak var open: UITapGestureRecognizer?
        /// Pencil로 긋는 중인 범위 (손을 떼면 저장).
        private var live: NSRange?
        private var start = 0
        /// 처음 닿은 자리. 끌기는 조금 움직인 뒤에야 시작되므로 닿는 순간을 따로 적어 둔다.
        private var touchDown: CGPoint?

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if g === pan { touchDown = touch.location(in: g.view) }
            if g === open, let v = g.view as? InkTextView { return hit(v, touch.location(in: v)) != nil }
            return true
        }

        /// 메모 열기 누르기는 글 보기 자체의 누르기(링크·고르기)와 함께 인식되게 한다 (아니면 글 보기 쪽이 가져감).
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            g === open
        }

        /// 점에 닿은 형광펜: 메모 표시 먼저, 그다음 칠한 글자 (겹치면 나중에 칠한 것).
        private func hit(_ v: InkTextView, _ p: CGPoint) -> Highlight? {
            if let r = v.memoRange(at: p), let h = located.last(where: { $0.range == r })?.highlight { return h }
            let i = index(v, p)
            return located.last(where: { NSLocationInRange(i, $0.range) || NSLocationInRange(i - 1, $0.range) })?.highlight
        }

        @objc func openTap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? InkTextView, let h = hit(v, g.location(in: v)) else { return }
            parent?.context.openMemo(h.id)
        }
        private var shown: NSAttributedString?

        /// 글이나 글꼴이 바뀔 때만 글을 다시 놓는다. 형광펜 띠는 `InkTextView`가 따로 그린다.
        func render(_ v: UITextView) {
            guard let parent else { return }
            let s = Self.build(parent.text, font: font, tint: tint)
            guard shown == nil || !s.isEqual(to: shown!) else { return }
            shown = s
            v.attributedText = s
            v.invalidateIntrinsicContentSize()
        }

        static func build(_ text: AttributedString, font body: UIFont, tint: UIColor) -> NSAttributedString {
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
            guard let v = g.view as? InkTextView else { return }
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
                    v.bands.append((r, parent.context.color.uiColor))  // 저장된 형광펜이 돌아올 때까지 깜빡이지 않게
                    parent.context.add(h)
                }
                live = nil
            default:
                live = nil
            }
            // 긋는 동안에는 글을 다시 놓지 않고 띠만 다시 그린다 (바로 따라오게).
            v.live = live.flatMap { r in parent.map { (r, $0.context.color.uiColor) } }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            // 형광펜 모드: 누른 글자를 덮는 형광펜 중 가장 위(나중에 칠한 것)를 지운다.
            guard let v = g.view as? InkTextView, let h = hit(v, g.location(in: v)) else { return }
            parent?.context.remove(h.id)
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
            if let first = overlapping.last {
                actions.append(UIAction(title: first.highlight.memo == nil ? "메모 달기" : "메모 보기", image: UIImage(systemName: "note.text")) { [weak v] _ in
                    parent.context.openMemo(first.highlight.id)
                    v?.selectedRange = NSRange(location: 0, length: 0)
                })
            }
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

/// 형광펜 띠를 글 위에 직접 그리는 문단 보기.
/// 글자 배경색(backgroundColor)은 줄 간격까지 덮어 띠가 두껍고 아래로 처져 보이므로 쓰지 않는다.
/// 띠는 줄마다 글자 높이(기준선 위 대문자 높이 + 조금)에 맞춘 둥근 사각형이다.
final class InkTextView: UITextView {
    /// 점 → 글자 위치를 정확히 재려고 TextKit 1(layoutManager)을 직접 짜서 넘긴다.
    /// `init(usingTextLayoutManager:)`는 하위 클래스의 저장 속성을 만들지 않으므로 쓰지 않는다.
    static func make() -> InkTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        return InkTextView(frame: .zero, textContainer: container)
    }

    var bands: [(NSRange, UIColor)] = [] { didSet { setNeedsLayout() } }
    /// 메모가 달린 형광펜 범위. 마지막 띠 끝에 작은 메모 표시를 단다.
    var memos: [NSRange] = [] { didSet { if oldValue != memos { setNeedsLayout() } } }
    private var memoIcons: [(range: NSRange, rect: CGRect)] = []
    private static let memoImage: CGImage? = UIImage(systemName: "note.text",
                                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))?
        .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
        .rendered()

    /// 점이 메모 표시(누르기 쉽게 넓힌 영역)에 닿으면 그 형광펜 범위.
    func memoRange(at p: CGPoint) -> NSRange? {
        memoIcons.last { $0.rect.insetBy(dx: -10, dy: -10).contains(p) }?.range
    }
    var live: (NSRange, UIColor)? { didSet { drawBands() } }
    var bandFont: UIFont = .preferredFont(forTextStyle: .body) { didSet { if oldValue != bandFont { setNeedsLayout() } } }
    /// 띠를 담는 보기. UITextView는 자기가 모르는 층(layer)을 떼어 내므로 층이 아니라 보기로 얹는다.
    private let bandView: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        drawBands()
    }

    private func drawBands() {
        // 띠는 글 위에 얹는다 (반투명이라 글자가 비쳐 보임).
        if bandView.superview !== self { addSubview(bandView) }
        if subviews.last !== bandView { bringSubviewToFront(bandView) }
        let bandLayer = bandView.layer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bandView.frame = CGRect(origin: .zero, size: contentSize == .zero ? bounds.size : CGSize(width: bounds.width, height: max(bounds.height, contentSize.height)))
        bandLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for (range, color) in bands + (live.map { [$0] } ?? []) {
            let path = UIBezierPath()
            for r in rects(for: range) { path.append(UIBezierPath(roundedRect: r, cornerRadius: 3)) }
            let shape = CAShapeLayer()
            shape.path = path.cgPath
            shape.fillColor = color.cgColor
            bandLayer.addSublayer(shape)
        }
        memoIcons = []
        for range in memos {
            guard let last = rects(for: range).last, let image = Self.memoImage else { continue }
            let size = CGSize(width: image.width, height: image.height).applying(.init(scaleX: 1 / traitCollection.displayScale, y: 1 / traitCollection.displayScale))
            // 각주 표시처럼 띠 오른쪽 위 모서리에 걸쳐 단다 (다음 글자를 가리지 않게).
            let x = min(last.maxX - size.width * 0.35, bounds.width - size.width * 0.5)
            let rect = CGRect(x: x, y: last.minY - size.height * 0.75, width: size.width, height: size.height)
            let icon = CALayer()
            icon.contents = image
            icon.contentsScale = traitCollection.displayScale
            icon.frame = rect
            bandLayer.addSublayer(icon)
            memoIcons.append((range, rect))
        }
        CATransaction.commit()
    }

    /// 범위가 걸친 줄마다 띠 하나. 높이는 글꼴에서 정해 굵은 글씨·일반 글씨가 섞여도 같다.
    private func rects(for range: NSRange) -> [CGRect] {
        let lm = layoutManager
        let all = NSRange(location: 0, length: textStorage.length)
        let chars = NSIntersectionRange(range, all)
        guard chars.length > 0 else { return [] }
        let glyphs = lm.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
        let cap = bandFont.capHeight
        var out: [CGRect] = []
        lm.enumerateLineFragments(forGlyphRange: glyphs) { line, _, container, lineGlyphs, _ in
            let g = NSIntersectionRange(lineGlyphs, glyphs)
            guard g.length > 0 else { return }
            let box = lm.boundingRect(forGlyphRange: g, in: container)
            let baseline = line.minY + lm.location(forGlyphAt: g.location).y
            let top = baseline - cap * 1.2
            let bottom = baseline + cap * 0.3
            out.append(CGRect(x: box.minX - 1, y: top, width: box.width + 2, height: bottom - top)
                .offsetBy(dx: self.textContainerInset.left, dy: self.textContainerInset.top))
        }
        return out
    }

    /// 감싼 스크롤 화면이 Pencil 끌기로 스크롤할지.
    func pencilScrolls(_ on: Bool) {
        var view = superview
        while let v = view, !(v is UIScrollView) { view = v.superview }
        guard let pan = (view as? UIScrollView)?.panGestureRecognizer else { return }
        let pencil = UITouch.TouchType.pencil.rawValue as NSNumber
        var types = pan.allowedTouchTypes
        if on, !types.contains(pencil) { types.append(pencil) }
        if !on { types.removeAll { $0 == pencil } }
        if types != pan.allowedTouchTypes { pan.allowedTouchTypes = types }
    }
}

private extension UIImage {
    /// 기호 이미지를 색을 입힌 비트맵으로 굽는다 (CALayer.contents에 쓰기 위해).
    func rendered() -> CGImage? {
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { _ in draw(at: .zero) }.cgImage
    }
}
