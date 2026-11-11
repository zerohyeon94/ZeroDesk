import Foundation

/// 오늘 Daily 한 파일에서 읽은 진행. 형식 약속은 볼트 AGENTS.md "저녁: Daily".
/// `nil`인 칸은 "읽을 수 없음"이다. 0%로 바꾸지 않는다 (0%는 "안 했다"로 읽힌다).
public struct DailyProgress: Codable, Equatable, Sendable {
    /// 개념·문제·복습(`없음`이면 뺀다) 각각 n/m의 평균, 0...1.
    public var today: Double?
    /// 선택 했음(true)/안 함(false). 선택 `없음`이거나 읽지 못하면 nil.
    public var choiceDone: Bool?
    /// `## 이번 주`의 학습한 날.
    public var studyDays: Int?
    /// 학습한 날 목표. 줄이 `n일`(분모 없음)이면 nil.
    public var studyGoal: Int?

    /// 모든 칸이 읽을 수 없음.
    public init() {}

    public static func path(year: Int, month: Int, day: Int) -> String {
        String(format: "Daily/%04d-%02d/%04d-%02d-%02d.md", year, month, year, month, day)
    }

    public static func parse(_ text: String) -> DailyProgress {
        var items: [String: (n: Int, m: Int)?] = [:]   // 라벨 → n/m. `없음`이면 .some(nil)
        var p = DailyProgress()
        var section = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") { section = line.dropFirst(3).trimmingCharacters(in: .whitespaces); continue }
            if section == "오늘 학습",
               let m = line.wholeMatch(of: #/- \*\*(개념|문제|복습|선택):\*\* (.*?)(?: · (\d+)/(\d+)| ?없음)/#) {
                if let n = m.3.flatMap({ Int($0) }), let d = m.4.flatMap({ Int($0) }) { items[String(m.1)] = (n, d) }
                else { items[String(m.1)] = .some(nil) }
            } else if section == "이번 주", let m = line.wholeMatch(of: #/- \*\*학습한 날:\*\* (\d+)(?:/(\d+)|일)/#) {
                p.studyDays = Int(m.1)
                p.studyGoal = m.2.flatMap { Int($0) }
            }
        }
        // 개념·문제는 n/m이어야 하고 복습은 n/m 또는 없음. 하나라도 못 읽으면 오늘 막대는 읽을 수 없음.
        if case let .some(.some(c)) = items["개념"], case let .some(.some(q)) = items["문제"], let r = items["복습"] {
            let scores = [c, q, r].compactMap { $0 }.filter { $0.m > 0 }.map { min(Double($0.n) / Double($0.m), 1) }
            if !scores.isEmpty { p.today = scores.reduce(0, +) / Double(scores.count) }
        }
        if case let .some(.some(s)) = items["선택"], s.m > 0 { p.choiceDone = s.n >= s.m }
        return p
    }
}
