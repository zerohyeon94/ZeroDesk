import Foundation
import Testing
@testable import ZeroDesk
import ZeroDeskCore

/// 최종 리뷰에서 나온 문제를 다시 일으키는 테스트.
@MainActor
struct ReviewFixTests {
    // Important 1: 옛 로컬 사본(.downloaded)이 있으면 기다리지 않고 바로 읽는다.
    @Test func waitsOnlyWhenNotDownloaded() {
        #expect(VaultAccess.mustWait(for: .notDownloaded))
        #expect(!VaultAccess.mustWait(for: .downloaded))
        #expect(!VaultAccess.mustWait(for: .current))
        #expect(!VaultAccess.mustWait(for: nil))
    }

    // Important 2: 일시적인 읽기 실패는 이전 홈 값을 덮지 않는다.
    @Test func readFailureKeepsPrevious() async {
        let good = await HomeSnapshot.make(paths: [HomeSnapshot.queuePath, HomeSnapshot.schedulePath], month: "2026-11") { p in
            p == HomeSnapshot.queuePath ? "## 2026-11 · T\n### A\n- [ ] a" : "## 다가오는 일정\n- 2026-12-01 · 행사 · X"
        }
        let after = await HomeSnapshot.make(paths: [HomeSnapshot.queuePath, HomeSnapshot.schedulePath], month: "2026-11",
                                            previous: good) { _ in throw VaultError.notDownloaded }
        #expect(after.month == good.month)
        #expect(!after.queueUnreadable)
        #expect(after.schedule == good.schedule)
        #expect(!after.scheduleMissing)
    }

    // Important 3: 켜진 채 볼트 폴더가 사라지면 accessLost.
    @Test func listMissingRootThrowsAccessLost() {
        let gone = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(throws: VaultError.accessLost) { try VaultAccess(defaults: UserDefaults(suiteName: UUID().uuidString)!).listFiles(in: gone) }
    }

    // Important 5: 지금 절 계산 (화면 위 100pt 안으로 올라온 마지막 절).
    @Test func currentSectionFromTops() {
        #expect(NoteReaderView.currentSection([0: -500, 1: -20, 2: 300]) == 1)
        #expect(NoteReaderView.currentSection([0: 10, 1: 400]) == 0)
        #expect(NoteReaderView.currentSection([:]) == 0)
    }

    // 재분류(Minor 1 → Important): 지난달 숫자를 이번 달처럼 보여 주지 않는다.
    @Test func staleMonthIsHidden() {
        let s = HomeSnapshot(month: QueueMonth(month: "2026-11", theme: "T", groups: []), monthSectionMissing: false,
                             queueUnreadable: false, yearGoal: nil, schedule: nil, scheduleMissing: true)
        #expect(s.month(for: "2026-11")?.theme == "T")
        #expect(s.month(for: "2026-12") == nil)
    }
}
