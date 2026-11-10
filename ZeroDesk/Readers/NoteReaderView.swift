import SwiftUI
import ZeroDeskCore

/// 길게 읽기: 절 표시줄(고정) + 절 번호·구분선 + 다음 절 버튼 + 이어 읽기 (스펙 5.3).
struct NoteReaderView: View {
    let doc: NoteDocument
    let path: String
    var heading: String?
    @Environment(VaultStore.self) private var store
    @State private var current = 0
    @State private var tops: [Int: CGFloat] = [:]
    @State private var restored = false

    private var titled: [NoteSection] { doc.sections.filter { !$0.title.isEmpty } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let title = doc.title {
                        Text(title).font(.largeTitle.bold()).padding(.bottom, 16)
                    }
                    ForEach(doc.sections) { section in
                        sectionView(section, proxy: proxy)
                            .id(section.id)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { tops[section.id] = $0 }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: 728, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if titled.count > 1 { sectionBar(proxy) }
            }
            .onChange(of: tops) { _, t in
                // 화면 위에서 100pt 안으로 올라온 마지막 절이 지금 절이다.
                let now = t.filter { $0.value <= 100 }.max { $0.key < $1.key }?.key ?? 0
                if now != current { current = now }
            }
            .onChange(of: current) { _, c in if restored { store.setLastSection(c, of: path) } }
            .task(id: path) {
                let target = heading.flatMap(doc.sectionIndex(forHeading:)) ?? store.lastSection(of: path)
                try? await Task.sleep(for: .milliseconds(50))
                if target > 0, target < doc.sections.count { proxy.scrollTo(target, anchor: .top) }
                restored = true
            }
        }
    }

    @ViewBuilder private func sectionView(_ s: NoteSection, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let n = titled.firstIndex(where: { $0.id == s.id }) {
                Divider().padding(.top, n == 0 && s.id == 1 && doc.sections[0].blocks.isEmpty ? 0 : 36)
                Text("\(n + 1). \(s.title)").font(.title2.bold()).padding(.top, 8)
            }
            BlocksView(blocks: s.blocks)
            if let n = titled.firstIndex(where: { $0.id == s.id }), n + 1 < titled.count {
                let next = titled[n + 1]
                Button { withAnimation { proxy.scrollTo(next.id, anchor: .top) } } label: {
                    Label("다음: \(next.title)", systemImage: "arrow.down")
                }
                .buttonStyle(.bordered).padding(.top, 8)
            }
        }
    }

    private func sectionBar(_ proxy: ScrollViewProxy) -> some View {
        let pos = (titled.firstIndex { $0.id == current } ?? titled.lastIndex { $0.id < current } ?? 0)
        return HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(titled.enumerated()), id: \.element.id) { i, s in
                        Button { withAnimation { proxy.scrollTo(s.id, anchor: .top) } } label: {
                            Text("\(i + 1) \(s.title)").lineLimit(1).font(.footnote)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(i == pos ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear), in: .capsule)
                                .fontWeight(i == pos ? .semibold : .regular)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("\(pos + 1) / \(titled.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            Menu {
                ForEach(Array(titled.enumerated()), id: \.element.id) { i, s in
                    Button("\(i + 1). \(s.title)") { proxy.scrollTo(s.id, anchor: .top) }
                }
            } label: { Image(systemName: "list.bullet") }
            .accessibilityLabel("목차")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
    }
}
