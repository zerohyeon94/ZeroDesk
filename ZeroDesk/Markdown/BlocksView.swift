import SwiftUI
import UIKit
import ZeroDeskCore

/// 마크다운 블록 목록을 그린다. 본문 폭 680pt, 줄 간격 6, 블록 사이 14pt (스펙 5.3).
/// 상자(테두리)는 코드 블록에만 쓴다.
struct BlocksView: View {
    let blocks: [Markup]

    init(blocks: [Markup]) { self.blocks = blocks }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks.indices, id: \.self) { BlockView(markup: blocks[$0], nested: false) }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}

private struct BlockView: View {
    let markup: Markup
    /// 목록·인용 안이면 굵은 글씨 문단 배경을 넣지 않는다 (카드 안 상자 겹침 방지).
    var nested = true
    @Environment(VaultStore.self) private var store

    var body: some View {
        switch markup {
        case let p as Paragraph:
            if p.childCount == 1, let img = p.child(at: 0) as? Markdown.Image {
                VaultImage(source: img.source ?? "", alt: img.plainText)
            } else if !nested, p.child(at: 0) is Strong {
                // 굵은 글씨로 시작하는 문단(핵심·주의)은 배경 상자 대신 왼쪽 세로줄로 표시한다.
                text(p).sideRule(.tint)
            } else {
                text(p)
            }
        case let h as Heading:
            Text(inlineText(h, index: store.index))
                .font(h.level <= 2 ? .title3.bold() : h.level == 3 ? .headline : .subheadline.bold())
                .padding(.top, 6)
        case let l as UnorderedList:
            ListBlock(items: Array(l.listItems), start: nil)
        case let l as OrderedList:
            ListBlock(items: Array(l.listItems), start: Int(l.startIndex))
        case let q as BlockQuote:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(q.children.enumerated()), id: \.offset) { BlockView(markup: $0.element) }
            }
            .sideRule(.secondary)
        case let c as CodeBlock:
            ScrollView(.horizontal) {
                Text(MonoGrid.text(c.code.hasSuffix("\n") ? String(c.code.dropLast()) : c.code))
                    .fixedSize()
                    .padding(12)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        case let t as Markdown.Table:
            TableBlock(table: t)
        case is ThematicBreak:
            Divider()
        case let h as HTMLBlock:
            Text(h.rawHTML).font(.callout).foregroundStyle(.secondary)
        default:
            Text(markup.format())
        }
    }

    private func text(_ m: Markup) -> some View {
        Text(inlineText(m, index: store.index)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    /// 인용·강조 문단: 상자 없이 왼쪽 세로줄(3pt)과 들여쓰기만 준다.
    func sideRule(_ style: some ShapeStyle) -> some View {
        padding(.leading, 14).padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Capsule().fill(style.opacity(0.6)).frame(width: 3) }
    }
}

private struct ListBlock: View {
    let items: [ListItem]
    let start: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(items[i], i)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items[i].children.enumerated()), id: \.offset) { BlockView(markup: $0.element) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func marker(_ item: ListItem, _ i: Int) -> some View {
        if let box = item.checkbox {
            Image(systemName: box == .checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(box == .checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        } else if let start {
            Text("\(start + i).").monospacedDigit().foregroundStyle(.secondary)
        } else {
            Text("•").foregroundStyle(.secondary)
        }
    }
}

private struct TableBlock: View {
    let table: Markdown.Table
    @Environment(VaultStore.self) private var store

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(table.head.cells.enumerated()), id: \.offset) { Text(inlineText($0.element, index: store.index)).bold() }
                }
                Divider()
                ForEach(Array(table.body.rows.enumerated()), id: \.offset) { row in
                    GridRow {
                        ForEach(Array(row.element.cells.enumerated()), id: \.offset) {
                            Text(inlineText($0.element, index: store.index)).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 320, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// `![[그림]]`: png·jpg·gif는 폭에 맞춰 보여 주고 누르면 확대. svg는 파일 이름만 (스펙 5.4).
private struct VaultImage: View {
    let source: String
    let alt: String
    @Environment(VaultStore.self) private var store
    @State private var image: UIImage?
    @State private var zoomed = false

    private var path: String? {
        guard let url = URL(string: source), let p = AppLink.parse(url) else { return nil }
        return store.index.resolve(p.target)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 8))
                    .onTapGesture { zoomed = true }
                    .accessibilityLabel(alt.isEmpty ? "그림" : alt)
            } else {
                Label(path.map { ($0 as NSString).lastPathComponent } ?? "그림을 찾지 못함", systemImage: "photo")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .task(id: path) {
            guard let path, ["png", "jpg", "jpeg", "gif"].contains((path as NSString).pathExtension.lowercased()),
                  let data = try? await store.data(of: path) else { return }
            image = UIImage(data: data)
        }
        .sheet(isPresented: $zoomed) {
            if let image { ZoomImage(image: image) }
        }
    }
}

private struct ZoomImage: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: 900 * scale)
            }
            .gesture(MagnifyGesture().onChanged { scale = min(4, max(1, $0.magnification)) })
            .toolbar { Button("닫기") { dismiss() } }
        }
    }
}
