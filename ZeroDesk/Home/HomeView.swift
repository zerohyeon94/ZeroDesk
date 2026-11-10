import SwiftUI
import ZeroDeskCore

/// 홈: 왼쪽 학습 상태(게이지·1년 목표·오늘 개념), 오른쪽 일정. 좁은 폭은 한 열 (스펙 4.1).
struct HomeView: View {
    var openInStudy: (String) -> Void
    @Environment(VaultStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView {
            if let home = store.home {
                if sizeClass == .regular && width > 700 {
                    let left = (width - 40 - 20) / 2.15
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 16) { gauge(home); yearGoal(home); today(home) }.frame(width: left)
                        schedule(home)
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 16) { gauge(home); schedule(home); today(home); yearGoal(home) }.padding(16)
                }
            } else {
                ProgressView("iCloud에서 받는 중").padding(.top, 80)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .refreshable { await store.refresh() }
    }

    private var monthKey: String {
        let t = todayKST()
        return String(format: "%04d-%02d", t.year ?? 0, t.month ?? 0)
    }

    // MARK: 왼쪽

    @ViewBuilder private func gauge(_ h: HomeSnapshot) -> some View {
        Card {
            if h.queueUnreadable {
                Button("형식을 읽지 못함 · 파일 열기") { openInStudy(HomeSnapshot.queuePath) }
            } else if let m = h.month(for: monthKey) {
                let t = todayKST()
                let pace = MonthPace.make(remainingItems: m.total - m.done, today: t, calendar: kstCalendar)
                Text("\(t.month ?? 0)월 · \(m.theme)").font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(m.done) / \(m.total)").font(.system(size: 44, weight: .bold).monospacedDigit())
                    Text("개념").font(.title3).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(m.done), total: Double(max(m.total, 1)))
                Text("남은 \(pace.remainingDays)일 · 하루 \(pace.perDay.formatted(.number.precision(.fractionLength(1))))개 속도 필요")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("이번 달 대기열이 아직 없음").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func yearGoal(_ h: HomeSnapshot) -> some View {
        if let goal = h.yearGoal {
            Card {
                Text("1년 목표").font(.subheadline.bold()).foregroundStyle(.secondary)
                Text(goal).font(.callout)
            }
        }
    }

    @ViewBuilder private func today(_ h: HomeSnapshot) -> some View {
        let path = h.month(for: monthKey)?.currentLink.flatMap(store.index.resolve)
        Card {
            Text("오늘 개념").font(.subheadline.bold()).foregroundStyle(.secondary)
            if let path {
                Button { openInStudy(path) } label: {
                    HStack {
                        Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension).font(.headline).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                Text("오늘 개념 없음").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 오른쪽

    private func schedule(_ h: HomeSnapshot) -> some View {
        let t = todayKST()
        return Card {
            Text("다가오는 일정").font(.headline)
            if h.scheduleMissing || h.schedule == nil {
                Text("주요 일정 파일이 아직 없음").foregroundStyle(.secondary)
            } else if let s = h.schedule {
                let up = s.upcoming(from: t)
                if up.isEmpty { Text("다가오는 일정 없음").font(.callout).foregroundStyle(.secondary) }
                ForEach(Array(up.enumerated()), id: \.offset) { _, e in ScheduleRow(entry: e, today: t) }
                let recent = s.recent(asOf: t)
                if !recent.isEmpty {
                    Text("최근 발표").font(.subheadline.bold()).foregroundStyle(.secondary).padding(.top, 10)
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, e in ScheduleRow(entry: e, today: t, past: true) }
                }
                if s.skippedLines > 0 {
                    Text("읽지 못한 줄 \(s.skippedLines)개").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
            }
        }
    }
}

private struct ScheduleRow: View {
    let entry: ScheduleEntry
    let today: DateComponents
    var past = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            Text(dateText).font(.subheadline.monospacedDigit()).frame(width: 52, alignment: .leading)
            Text(entry.title).lineLimit(2)
            KindTag(kind: entry.kind)
            Spacer(minLength: 4)
            if entry.estimated { Text("추정").font(.caption).foregroundStyle(.secondary) }
            if !past, let d = dDay(entry.date, from: today) {
                Text(d == 0 ? "D-day" : "D-\(d)").font(.subheadline.monospacedDigit().bold())
            }
            if let src = entry.source {
                Button { openURL(src) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain).foregroundStyle(.tint).accessibilityLabel("출처")
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String {
        switch entry.date {
        case let .day(_, m, d): "\(m)/\(d)"
        case let .month(_, m): "\(m)월"
        }
    }
}

private struct KindTag: View {
    let kind: ScheduleKind
    var color: Color {
        switch kind {
        case .exam: .red
        case .tech: .blue
        case .earnings: .green
        case .event: .orange
        }
    }

    var body: some View {
        Text(kind.rawValue).font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
    }
}
