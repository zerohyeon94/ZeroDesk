import Foundation

/// `Schedule/주요 일정.md`의 종류 칸. 모르는 종류는 `.event`로 본다 (스펙 7.3).
public enum ScheduleKind: String, Equatable, Codable, Sendable {
    case exam = "시험", tech = "기술", earnings = "실적", event = "행사"
}

/// 날짜 칸. `YYYY-MM-DD` 또는 월만 아는 `YYYY-MM`. 비교할 때 `.month`는 그 달 1일이다.
public enum ScheduleDate: Comparable, Equatable, Codable, Sendable {
    case day(year: Int, month: Int, day: Int)
    case month(year: Int, month: Int)

    var key: (Int, Int, Int) {
        switch self {
        case let .day(y, m, d): (y, m, d)
        case let .month(y, m): (y, m, 1)
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.key < b.key }

    static func parse(_ s: String) -> ScheduleDate? {
        guard s.count == 7 || s.count == 10 else { return nil }
        let p = s.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard p.count == (s.count == 7 ? 2 : 3), (1...12).contains(p[1]) else { return nil }
        if p.count == 2 { return .month(year: p[0], month: p[1]) }
        guard let d = gregorian.date(from: DateComponents(year: p[0], month: p[1], day: p[2])),
              gregorian.component(.day, from: d) == p[2] else { return nil }
        return .day(year: p[0], month: p[1], day: p[2])
    }
}

public struct ScheduleEntry: Equatable, Codable, Sendable {
    public var date: ScheduleDate
    public var kind: ScheduleKind
    public var title: String
    public var estimated: Bool
    public var source: URL?
}

public struct ScheduleFile: Equatable, Codable, Sendable {
    public var upcoming: [ScheduleEntry]
    public var recent: [ScheduleEntry]
    public var skippedLines: Int

    /// `## 다가오는 일정` / `## 최근 발표` 절 안의 `- ` 줄만 읽는다. 다른 절은 무시한다.
    public static func parse(_ text: String) -> ScheduleFile {
        var file = ScheduleFile(upcoming: [], recent: [], skippedLines: 0)
        var section: WritableKeyPath<ScheduleFile, [ScheduleEntry]>?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let name = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                section = name == "다가오는 일정" ? \.upcoming : name == "최근 발표" ? \.recent : nil
                continue
            }
            guard let section, line.hasPrefix("- ") else { continue }
            if let entry = entry(String(line.dropFirst(2))) { file[keyPath: section].append(entry) }
            else { file.skippedLines += 1 }
        }
        return file
    }

    static func entry(_ body: String) -> ScheduleEntry? {
        var parts = body.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3, let date = ScheduleDate.parse(parts[0]) else { return nil }
        var source: URL?
        if parts.count >= 4, let last = parts.last, last.hasPrefix("["), last.hasSuffix(")"),
           let open = last.range(of: "](") {
            source = URL(string: String(last[open.upperBound..<last.index(before: last.endIndex)]))
            parts.removeLast()
        }
        var title = parts[2...].joined(separator: " · ")
        let estimated = title.hasSuffix("(추정)")
        if estimated { title = title.dropLast("(추정)".count).trimmingCharacters(in: .whitespaces) }
        guard !title.isEmpty else { return nil }
        return ScheduleEntry(date: date, kind: ScheduleKind(rawValue: parts[1]) ?? .event,
                             title: title, estimated: estimated, source: source)
    }
}

/// 날짜 계산은 KST 그레고리력으로 한다 (볼트 규칙이 KST 기준).
let gregorian: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
}()

private func dateKey(_ c: DateComponents) -> (Int, Int, Int) { (c.year ?? 0, c.month ?? 0, c.day ?? 0) }

extension ScheduleFile {
    /// 오늘 이후 날짜순. 월만 아는 일정은 이번 달이면 아직 포함한다.
    public func upcoming(from today: DateComponents, limit: Int = 8) -> [ScheduleEntry] {
        let t = dateKey(today)
        return upcoming.filter {
            switch $0.date {
            case .day: $0.date.key >= t
            case let .month(y, m): (y, m) >= (t.0, t.1)
            }
        }
        .sorted { $0.date < $1.date }
        .prefix(limit).map { $0 }
    }

    /// 최근 `days`일(오늘 포함) 발표, 최신 먼저.
    public func recent(asOf today: DateComponents, days: Int = 14, limit: Int = 5) -> [ScheduleEntry] {
        guard let now = gregorian.date(from: today),
              let from = gregorian.date(byAdding: .day, value: -(days - 1), to: now) else { return [] }
        let cut = dateKey(gregorian.dateComponents([.year, .month, .day], from: from))
        return recent.filter { $0.date.key >= cut }
            .sorted { $1.date < $0.date }
            .prefix(limit).map { $0 }
    }
}

/// 날짜까지 남은 날. 월만 아는 일정은 `nil`.
public func dDay(_ date: ScheduleDate, from today: DateComponents) -> Int? {
    guard case let .day(y, m, d) = date,
          let a = gregorian.date(from: today),
          let b = gregorian.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
    return gregorian.dateComponents([.day], from: a, to: b).day
}
