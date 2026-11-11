import PencilKit
import SwiftUI
import ZeroDeskCore

/// 길게 읽기: 절 표시줄(고정) + 절 번호·구분선 + 다음 절 버튼 + 이어 읽기 (스펙 5.3).
/// 본문 폭이 680pt로 고정되는 넓은 화면에서는 절마다 Pencil 필기 층을 얹는다 (md 파일은 그대로).
struct NoteReaderView: View {
    let doc: NoteDocument
    let path: String
    var heading: String?
    @Environment(VaultStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var current = 0
    /// 절 위치는 화면을 다시 그리지 않도록 참조 상자에 둔다 (스크롤 매 프레임 갱신).
    @State private var tops = Tops()
    final class Tops { var values: [Int: CGFloat] = [:] }
    @State private var restored = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var ink: NoteInk?
    @State private var inking = false
    @State private var toolPicker = PKToolPicker()
    @State private var readerWidth: CGFloat = 0

    /// 본문 폭(680pt)이 고정되는 넓이에서만 필기를 쓴다. 폭이 바뀌면 줄 바뀜이 달라져 필기가 어긋나기 때문.
    static let inkMinWidth: CGFloat = 728
    private var inkAvailable: Bool { readerWidth >= Self.inkMinWidth }
    /// 그린 때의 글자 배치. 글자 크기가 바뀌면 필기가 어긋났다고 본다.
    private var inkLayout: String { "680|\(typeSize.oneLarger)" }

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
                    if !inkAvailable, let ink, !ink.file.sections.isEmpty {
                        Label("필기는 넓은 화면에서 보임 (대기열을 접거나 iPad에서)", systemImage: "pencil.tip")
                            .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 12)
                    }
                    if let ink, ink.saveFailed {
                        Label("필기를 저장하지 못함. 잠시 뒤 다시 저장함", systemImage: "exclamationmark.icloud")
                            .font(.footnote).foregroundStyle(.red).padding(.bottom, 12)
                    }
                    ForEach(doc.sections) { section in
                        inkedSection(section, proxy: proxy)
                            .id(section.id)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: {
                                tops.values[section.id] = $0
                                let now = Self.currentSection(tops.values)
                                if now != current { current = now }
                            }
                    }
                }
                // 본문은 시스템 글자 크기보다 한 단계 크게 (기본 17pt → 19pt). 시스템 설정을 바꾸면 함께 따라간다.
                .dynamicTypeSize(typeSize.oneLarger)
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: 728, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if titled.count > 1 { sectionBar(proxy) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { readerWidth = $0 }
            .onChange(of: inkAvailable) { _, ok in if !ok { inking = false } }
            .onChange(of: scenePhase) { _, p in if p != .active { Task { await ink?.flush() } } }
            .onDisappear { Task { [ink] in await ink?.flush() } }
            .task(id: path) {
                let i = NoteInk(notePath: path, store: store)
                ink = i
                await i.load()
            }
            .toolbar {
                if inkAvailable, let ink {
                    ToolbarItem(placement: .primaryAction) {
                        Button { inking.toggle() } label: {
                            Image(systemName: inking ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                        }
                        .disabled(ink.state != .ready)
                        .accessibilityLabel(ink.state == .failed ? "필기를 읽지 못함" : inking ? "필기 끝내기" : "필기하기")
                    }
                }
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

    /// 절 + 그 위의 필기 층. 본문이 바뀐 절은 필기를 흐리게 보여 주고 아래에 고르는 줄을 단다.
    /// 고르는 줄은 절 아래에 두어 이 절 필기의 위치를 밀지 않는다.
    @ViewBuilder private func inkedSection(_ s: NoteSection, proxy: ScrollViewProxy) -> some View {
        let key = doc.inkKeys[s.id] ?? s.title
        let hash = s.inkHash
        if inkAvailable, let ink, ink.state == .ready {
            let data = ink.data(key)
            let stale = data != nil && !ink.file.matches(key, hash: hash, layout: inkLayout)
            VStack(alignment: .leading, spacing: 10) {
                sectionView(s, proxy: proxy)
                    .overlay {
                        InkCanvas(data: data, editing: inking, stale: stale, focused: s.id == current,
                                  toolPicker: toolPicker) { d, bytes in
                            ink.set(d, data: bytes, key: key, hash: hash, layout: inkLayout)
                        }
                    }
                if stale {
                    HStack(spacing: 12) {
                        Label("본문이 바뀌어 필기 위치가 어긋났을 수 있음", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("그대로 쓰기") { ink.accept(key: key, hash: hash, layout: inkLayout) }
                        Button("지우기", role: .destructive) { ink.clear(key: key) }
                    }
                    .font(.footnote).buttonStyle(.borderless)
                }
            }
        } else {
            sectionView(s, proxy: proxy)
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

extension DynamicTypeSize {
    /// 한 단계 큰 글자 크기 (가장 큰 단계면 그대로).
    var oneLarger: DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return self }
        return all[i + 1]
    }
}
