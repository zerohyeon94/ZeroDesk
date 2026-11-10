import SwiftUI
import ZeroDeskCore

/// 학습 대기열 진행 보기: 묶음별 완료/전체, 지금 하는 항목 강조, 다른 달은 접기, "원문 보기" (스펙 5.1).
struct QueueProgressView: View {
    let text: String
    let path: String
    @State private var raw = false
    @Environment(\.openURL) private var openURL

    private var monthKey: String {
        let t = todayKST()
        return String(format: "%04d-%02d", t.year ?? 0, t.month ?? 0)
    }

    var body: some View {
        let month = QueueProgress.parse(text, month: monthKey)
        Group {
            if raw || month == nil {
                VStack(spacing: 0) {
                    if month == nil {
                        Text("이번 달 대기열이 아직 없음").font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    NoteReaderView(doc: NoteDocument.parse(text), path: path)
                }
            } else if let month {
                progress(month)
            }
        }
        .toolbar {
            if month != nil {
                ToolbarItem(placement: .primaryAction) {
                    Toggle("원문 보기", isOn: $raw).toggleStyle(.button)
                }
            }
        }
    }

    private func progress(_ m: QueueMonth) -> some View {
        let doc = NoteDocument.parse(text)
        let others = QueueProgress.otherSections(text, excluding: monthKey)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(m.month) · \(m.theme)").font(.title3.bold())
                    Text("\(m.done) / \(m.total) 완료").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                ForEach(Array(m.groups.enumerated()), id: \.offset) { _, g in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(g.name).font(.headline)
                            Spacer()
                            Text("\(g.done) / \(g.total)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(g.done), total: Double(max(g.total, 1)))
                        ForEach(Array(g.items.enumerated()), id: \.offset) { _, item in row(item, current: item.link != nil && item.link == m.currentLink && !item.done) }
                    }
                }
                ForEach(others, id: \.self) { title in
                    DisclosureGroup(title) {
                        if let s = doc.sections.first(where: { $0.title == title }) { BlocksView(blocks: s.blocks).padding(.top, 8) }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 728, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func row(_ item: QueueItem, current: Bool) -> some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.done ? "checkmark.circle.fill" : current ? "smallcircle.filled.circle" : "circle")
                .foregroundStyle(item.done || current ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(item.text).foregroundStyle(item.done ? .secondary : .primary).multilineTextAlignment(.leading)
            if item.link != nil { Spacer(minLength: 4); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, current ? 8 : 2).padding(.horizontal, current ? 10 : 0)
        .background(current ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        if let link = item.link {
            Button { openURL(AppLink.open(link)) } label: { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}
