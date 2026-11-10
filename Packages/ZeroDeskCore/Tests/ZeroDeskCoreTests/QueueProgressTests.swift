import Foundation
import Testing
import ZeroDeskCore

struct QueueProgressTests {
    @Test func fixtureNovember() throws {
        let m = try #require(QueueProgress.parse(try fixture("Schedule/학습 대기열.md"), month: "2026-11"))
        #expect(m.month == "2026-11")
        #expect(m.theme == "시스템 전체 한 바퀴")
        #expect(m.total == 29)
        #expect(m.done == 0)
        #expect(m.groups.first?.name == "0. 전체")
        #expect(m.groups.first?.total == 5)
        #expect(m.currentLink == "Learning/개념/2026-11-03 엣지-중앙 서버 구조")
        #expect(m.groups.first?.items.first?.text == "엣지-중앙 서버 구조: 장비 안의 AI 엔진·에이전트와 중앙 서버의 역할 나누기")
    }

    @Test func doneCounts() throws {
        let m = try #require(QueueProgress.parse("## 2026-11 · T\n### A\n- [x] a\n- [ ] b\n### B\n- [X] c", month: "2026-11"))
        #expect(m.done == 2)
        #expect(m.total == 3)
    }

    @Test func noMonthSection() {
        #expect(QueueProgress.parse("## 2026-11 · T\n### A\n- [x] a", month: "2026-12") == nil)
    }

    @Test func currentIsLastUnfinishedLinked() throws {
        let text = "## 2026-11 · T\n### A\n- [x] a → [[A]]\n- [ ] b → [[B|비]]\n- [ ] c → [[C]]\n- [ ] d"
        #expect(try #require(QueueProgress.parse(text, month: "2026-11")).currentLink == "C")
    }

    @Test func otherSectionsFolded() throws {
        let other = QueueProgress.otherSections(try fixture("Schedule/학습 대기열.md"), excluding: "2026-11")
        #expect(other.contains("다음 달 이후 (월말 확인 때 확정)"))
        #expect(!other.contains { $0.hasPrefix("2026-11") })
    }

    @Test func yearGoalFixture() throws {
        #expect(YearGoal.line(in: try fixture("Schedule/월별 목표 (2026-11 ~ 2027-10).md"))
                == "플랫폼 지도 80% 이상 ○ · 에이전트 기능 사례 3 · AI 프로토타입 1 · 자격증 2개 이상 · 블로그 3")
        #expect(YearGoal.line(in: "# 없음") == nil)
    }

    @Test func paceMidMonth() {
        let p = MonthPace.make(remainingItems: 29, today: DateComponents(year: 2026, month: 11, day: 10), calendar: Calendar(identifier: .gregorian))
        #expect(p.remainingDays == 21)
        #expect(p.perDay == 1.4)
    }

    @Test func paceLastDay() {
        let p = MonthPace.make(remainingItems: 3, today: DateComponents(year: 2026, month: 11, day: 30), calendar: Calendar(identifier: .gregorian))
        #expect(p.remainingDays == 1)
        #expect(p.perDay == 3.0)
    }

    @Test func monthBoundaryFirstDayNoSection() throws {
        // 새 달 1일, 봇이 아직 그 달 절을 만들지 않음
        #expect(QueueProgress.parse(try fixture("Schedule/학습 대기열.md"), month: "2026-12") == nil)
    }
}
