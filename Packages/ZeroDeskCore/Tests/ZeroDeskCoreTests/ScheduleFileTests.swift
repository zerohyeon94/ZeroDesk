import Foundation
import Testing
import ZeroDeskCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> DateComponents { DateComponents(year: y, month: m, day: d) }

struct ScheduleFileTests {
    @Test func parsesFixture() throws {
        let f = ScheduleFile.parse(try fixture("Schedule/주요 일정.md"))
        #expect(f.upcoming.count == 4)
        let first = try #require(f.upcoming.first)
        #expect(first.date == .month(year: 2027, month: 3))
        #expect(first.kind == .exam)
        #expect(first.title == "SQLD")
        #expect(first.estimated)
        #expect(f.recent.isEmpty)
        #expect(f.skippedLines == 0)
    }

    @Test func parsesDayAndSource() throws {
        let f = ScheduleFile.parse("## 최근 발표\n- 2026-11-09 · 기술 · Fable 5.2 출시 · [출처](https://example.com)")
        let e = try #require(f.recent.first)
        #expect(e.date == .day(year: 2026, month: 11, day: 9))
        #expect(e.source?.host == "example.com")
        #expect(e.title == "Fable 5.2 출시")
        #expect(e.kind == .tech)
    }

    @Test func unknownKindIsEvent() {
        let f = ScheduleFile.parse("## 다가오는 일정\n- 2026-12-01 · 발표회 · X")
        #expect(f.upcoming.first?.kind == .event)
    }

    @Test func skipsBadLines() {
        let f = ScheduleFile.parse("## 다가오는 일정\n- 내일 · 시험 · X\n- 2026-13-01 · 시험 · Y\n- 2026-12-01 · 시험 · Z")
        #expect(f.upcoming.count == 1)
        #expect(f.skippedLines == 2)
    }

    @Test func upcomingSortsAndFilters() {
        let f = ScheduleFile.parse("""
        ## 다가오는 일정
        - 2027-03 · 시험 · D
        - 2026-11-20 · 행사 · B
        - 2026-11-09 · 행사 · A
        - 2026-11 · 행사 · C
        """)
        #expect(f.upcoming(from: day(2026, 11, 10)).map(\.title) == ["C", "B", "D"])
    }

    @Test func upcomingLimit() {
        let lines = (1...12).map { "- 2026-12-\(String(format: "%02d", $0)) · 행사 · \($0)" }.joined(separator: "\n")
        let f = ScheduleFile.parse("## 다가오는 일정\n" + lines)
        #expect(f.upcoming(from: day(2026, 11, 10)).count == 8)
    }

    @Test func recentWindow() {
        let f = ScheduleFile.parse("""
        ## 최근 발표
        - 2026-10-27 · 기술 · A
        - 2026-11-09 · 기술 · C
        - 2026-10-28 · 기술 · B
        """)
        #expect(f.recent(asOf: day(2026, 11, 10)).map(\.title) == ["C", "B"])
    }

    @Test func dDayCounts() {
        #expect(dDay(.day(year: 2026, month: 11, day: 20), from: day(2026, 11, 10)) == 10)
        #expect(dDay(.month(year: 2027, month: 3), from: day(2026, 11, 10)) == nil)
    }

    @Test func emptyText() {
        let f = ScheduleFile.parse("")
        #expect(f.upcoming.isEmpty && f.recent.isEmpty && f.skippedLines == 0)
    }
}
