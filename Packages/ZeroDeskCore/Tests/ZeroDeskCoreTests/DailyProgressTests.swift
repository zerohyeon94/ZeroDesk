import Testing
import ZeroDeskCore

/// 볼트 `Claude/2026-11-12 ZeroDesk 진행 막대 형식.md`의 예시 Daily 세 시점.
private let link = "[[Learning/개념/2026-11-03 엣지-중앙 서버 구조|엣지-중앙 서버 구조]] (SYS-01)"
private let choice = "플랫폼 지도: '전체' 구성 요소 칸 하나 채우기 (5분)"

private func daily(concept: String, problem: String, choice c: String, days: String) -> String {
    """
    # 2026-11-12 (목)

    ## 오늘 학습

    - **개념:** \(concept)
    - **문제:** \(problem)
    - **복습:** 없음
    - **선택:** \(c)

    ## 오늘 한 일

    (저녁 23:30에 비서가 채운다)

    ## 이번 주

    - **기간:** 11-09 (월) ~ 11-15 (일)
    - **학습한 날:** \(days)
    - **끝낸 개념:** 0개
    """
}

struct DailyProgressTests {
    @Test func morning() {
        let p = DailyProgress.parse(daily(concept: "\(link) · 0/1", problem: "맞힘 0 · 0/2",
                                          choice: "\(choice) · 0/1", days: "2/4"))
        #expect(p.today == 0)
        #expect(p.choiceDone == false)
        #expect(p.studyDays == 2 && p.studyGoal == 4)
    }

    @Test func midday() {
        let p = DailyProgress.parse(daily(concept: "\(link) · 0/1", problem: "맞힘 1 · 2/2",
                                          choice: "\(choice) · 1/1", days: "3/4"))
        #expect(p.today == 0.5)
        #expect(p.choiceDone == true)
        #expect(p.studyDays == 3 && p.studyGoal == 4)
    }

    @Test func evening() {
        let p = DailyProgress.parse(daily(concept: "\(link) 완료 · 1/1", problem: "맞힘 1 · 2/2",
                                          choice: "\(choice) 했음 · 1/1", days: "3/4"))
        #expect(p.today == 1)
        #expect(p.choiceDone == true)
    }

    @Test func reviewCountsWhenPresent() {
        let text = "## 오늘 학습\n- **개념:** x · 0/1\n- **문제:** 맞힘 2 · 2/3\n- **복습:** 맞힘 1 · 1/1\n- **선택:** 없음"
        let p = DailyProgress.parse(text)
        #expect(abs(p.today! - (0 + 2.0 / 3 + 1) / 3) < 1e-9)
        #expect(p.choiceDone == nil)
        #expect(p.studyDays == nil)
    }

    /// 지금 볼트에 있는 옛 형식 (2026-11-10 아침판). 0%가 아니라 읽을 수 없음이어야 한다.
    @Test func oldFormatIsUnreadable() {
        let text = """
        ## 오늘 학습

        - **개념:** \(link) — 오늘 읽기 (어제 것 이어서)
        - **문제:** 오늘 3개 · #교육에서 푼다
        - **복습:** 없음
        - **선택:** \(choice)

        ## 이번 주

        (저녁 23:30에 비서가 채운다)
        """
        let p = DailyProgress.parse(text)
        #expect(p.today == nil)
        #expect(p.choiceDone == nil)
        #expect(p.studyDays == nil)
    }

    @Test func weekWithoutGoal() {
        let p = DailyProgress.parse("## 이번 주\n- **학습한 날:** 3일")
        #expect(p.studyDays == 3 && p.studyGoal == nil)
        #expect(p.today == nil)
    }

    @Test func path() {
        #expect(DailyProgress.path(year: 2026, month: 11, day: 2) == "Daily/2026-11/2026-11-02.md")
    }
}
