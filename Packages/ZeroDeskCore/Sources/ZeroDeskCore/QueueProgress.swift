import Foundation

/// 대기열 항목 한 줄. `link`는 `→ [[대상|…]]`의 `대상` (스펙 7.1).
public struct QueueItem: Equatable, Codable, Sendable {
    public var text: String
    public var done: Bool
    public var link: String?
}

public struct QueueGroup: Equatable, Codable, Sendable {
    public var name: String
    public var items: [QueueItem]
    public var done: Int { items.filter(\.done).count }
    public var total: Int { items.count }
}

public struct QueueMonth: Equatable, Codable, Sendable {
    public var month: String
    public var theme: String
    public var groups: [QueueGroup]
    public var done: Int { groups.map(\.done).reduce(0, +) }
    public var total: Int { groups.map(\.total).reduce(0, +) }
    /// 링크가 붙은 미완료 항목 중 마지막 것 = 오늘 개념.
    public var currentLink: String? { groups.flatMap(\.items).last { !$0.done && $0.link != nil }?.link }
}

public enum QueueProgress {
    /// `## <month> · 주제` 절부터 다음 `## ` 전까지 읽는다. 절이 없으면 `nil`.
    public static func parse(_ text: String, month: String) -> QueueMonth? {
        var result: QueueMonth?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if result != nil { break }
                let head = line.dropFirst(3)
                guard head.hasPrefix(month) else { continue }
                let theme = head.range(of: " · ").map { String(head[$0.upperBound...]) } ?? ""
                result = QueueMonth(month: month, theme: theme.trimmingCharacters(in: .whitespaces), groups: [])
            } else if result != nil, line.hasPrefix("### ") {
                result!.groups.append(QueueGroup(name: String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces), items: []))
            } else if result != nil, let item = item(line) {
                if result!.groups.isEmpty { result!.groups.append(QueueGroup(name: "", items: [])) }
                result!.groups[result!.groups.count - 1].items.append(item)
            }
        }
        return result
    }

    /// 이번 달이 아닌 `## ` 절 제목들 (접어서 보여 줄 것).
    public static func otherSections(_ text: String, excluding month: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("## ") }
            .map { String($0.dropFirst(3)) }
            .filter { !$0.hasPrefix(month) }
    }

    static func item(_ line: String) -> QueueItem? {
        let mark = line.prefix(6)
        guard mark == "- [ ] " || mark == "- [x] " || mark == "- [X] " else { return nil }
        var text = String(line.dropFirst(6))
        var link: String?
        if let arrow = text.range(of: "→ [["), let end = text.range(of: "]]", range: arrow.upperBound..<text.endIndex) {
            let inner = text[arrow.upperBound..<end.lowerBound]
            link = String(inner.prefix { $0 != "|" && $0 != "#" })
            text = text[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        return QueueItem(text: text, done: mark != "- [ ] ", link: link)
    }
}

public enum YearGoal {
    /// `> 1년 목표:` 뒤의 글 (스펙 7.2).
    public static func line(in text: String) -> String? {
        let prefix = "> 1년 목표:"
        return text.split(separator: "\n").first { $0.hasPrefix(prefix) }
            .map { $0.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) }
    }
}

public struct MonthPace: Equatable, Sendable {
    public var remainingDays: Int
    public var perDay: Double
}

extension MonthPace {
    /// 남은 날은 오늘 포함, 하루 속도는 소수 한 자리 반올림 (스펙 4.1).
    public static func make(remainingItems: Int, today: DateComponents, calendar: Calendar) -> MonthPace {
        let date = calendar.date(from: today) ?? .now
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let remaining = max(1, days - (today.day ?? 1) + 1)
        return MonthPace(remainingDays: remaining, perDay: (Double(remainingItems) / Double(remaining) * 10).rounded() / 10)
    }
}
