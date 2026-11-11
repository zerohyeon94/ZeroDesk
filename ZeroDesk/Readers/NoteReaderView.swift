import SwiftUI
import ZeroDeskCore

/// 길게 읽기: 절 표시줄(고정) + 절 번호·구분선 + 다음 절 버튼 + 이어 읽기 (스펙 5.3).
struct NoteReaderView: View {
    let doc: NoteDocument
    let path: String
    var heading: String?
    @Environment(VaultStore.self) private var store
    @State private var current = 0
    /// 절 위치는 화면을 다시 그리지 않도록 참조 상자에 둔다 (스크롤 매 프레임 갱신).
    @State private var tops = Tops()
    final class Tops { var values: [Int: CGFloat] = [:] }
    @State private var restored = false

    /// 화면 위에서 100pt 안으로 올라온 마지막 절이 지금 절이다.
    static func currentSection(_ tops: [Int: CGFloat]) -> Int {
        tops.filter { $0.value <= 100 }.max { $0.key < $1.key }?.key ?? 0
    }

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
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: {
                                tops.values[section.id] = $0
                                let now = Self.currentSection(tops.values)
                                if now != current { current = now }
                            }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: 728, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if titled.count > 1 { sectionBar(proxy) }
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
        // 절 이름을 한 줄로 늘어놓지 않고 "지금 절" 하나와 얇은 진행 막대만 보인다. 누르면 절 목록이 열린다.
        return VStack(spacing: 0) {
            Menu {
                ForEach(Array(titled.enumerated()), id: \.element.id) { i, s in
                    Button { withAnimation { proxy.scrollTo(s.id, anchor: .top) } } label: {
                        if i == pos { Label("\(i + 1). \(s.title)", systemImage: "checkmark") } else { Text("\(i + 1). \(s.title)") }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("\(pos + 1) / \(titled.count)").monospacedDigit().foregroundStyle(.secondary)
                    Text(titled.indices.contains(pos) ? titled[pos].title : "").fontWeight(.semibold).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("절 \(pos + 1) / \(titled.count), 목차 열기")
            .padding(.horizontal, 24)
            .frame(maxWidth: 728)
            .frame(maxWidth: .infinity)
            GeometryReader { g in
                Rectangle().fill(.tint).frame(width: g.size.width * CGFloat(pos + 1) / CGFloat(max(titled.count, 1)))
                    .animation(.easeOut(duration: 0.2), value: pos)
            }
            .frame(height: 2)
        }
        .background(.bar)
    }
}
