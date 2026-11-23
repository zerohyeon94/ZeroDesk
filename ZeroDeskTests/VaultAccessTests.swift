import Foundation
import Testing
@testable import ZeroDesk
import ZeroDeskCore

@MainActor
struct VaultAccessTests {
    let defaults: UserDefaults
    let access: VaultAccess
    let root: URL

    init() throws {
        let suite = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        access = VaultAccess(defaults: defaults)
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func touch(_ rel: String) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    @Test func listsSkipsHidden() throws {
        for p in [".obsidian/a.md", "Daily/b.md", "Assets/c.png", "x.txt", ".hidden.md"] { try touch(p) }
        #expect(try access.listFiles(in: root).map(\.path) == ["Assets/c.png", "Daily/b.md"])
    }

    @Test func listsICloudPlaceholderByRealName() throws {
        try touch("Daily/.c.md.icloud")
        #expect(try access.listFiles(in: root).map(\.path) == ["Daily/c.md"])
    }

    @Test func restoreWithoutBookmarkThrowsNoFolder() {
        #expect(throws: VaultError.noFolder) { try access.restore() }
    }

    @Test func restoreRoundTrip() throws {
        try access.save(folder: root)
        #expect(try access.restore().standardizedFileURL.lastPathComponent == root.lastPathComponent)
    }

    @Test func restoreStaleThrowsAccessLost() throws {
        try access.save(folder: root)
        try FileManager.default.removeItem(at: root)
        #expect(throws: VaultError.accessLost) { try access.restore() }
    }

    @Test func readsText() async throws {
        try "안녕".write(to: root.appending(path: "a.md"), atomically: true, encoding: .utf8)
        #expect(try await access.readText("a.md", root: root) == "안녕")
    }

    @Test func readMissingFileFails() async {
        do {
            _ = try await access.readText("없음.md", root: root, timeout: .milliseconds(200))
            Issue.record("던지지 않음")
        } catch let e as VaultError {
            #expect(e == .unreadable || e == .notDownloaded)
        } catch { Issue.record("다른 오류 \(error)") }
    }

    @Test func lastSectionRoundTrip() {
        let store = VaultStore(access: access)
        store.setLastSection(3, of: "a.md")
        #expect(store.lastSection(of: "a.md") == 3)
        #expect(store.lastSection(of: "b.md") == 0)
    }

    @Test func homeSnapshotFromFiles() async throws {
        try "## 2026-11 · T\n### A\n- [x] a\n- [ ] b → [[N]]".write(to: root.appending(path: "q.md"), atomically: true, encoding: .utf8)
        let snap = await HomeSnapshot.make(paths: ["Schedule/학습 대기열.md"], month: "2026-11") { _ in
            try String(contentsOf: root.appending(path: "q.md"), encoding: .utf8)
        }
        #expect(snap.month?.total == 2)
        #expect(snap.month?.currentLink == "N")
        #expect(!snap.monthSectionMissing && !snap.queueUnreadable)
        #expect(snap.scheduleMissing)
        #expect(snap.yearGoal == nil)
    }

    @Test func homeSnapshotMonthMissingAndUnreadable() async {
        let missing = await HomeSnapshot.make(paths: ["Schedule/학습 대기열.md"], month: "2026-12") { _ in "## 2026-11 · T\n- [ ] a" }
        #expect(missing.monthSectionMissing && missing.month == nil)
        let broken = await HomeSnapshot.make(paths: ["Schedule/학습 대기열.md"], month: "2026-11") { _ in throw VaultError.unreadable }
        #expect(broken.queueUnreadable)
    }

    @Test func homeSnapshotDaily() async {
        let today = "Daily/2026-11/2026-11-12.md"
        let text = "## 오늘 학습\n- **개념:** x · 0/1\n- **문제:** 맞힘 1 · 2/2\n- **복습:** 없음\n## 이번 주\n- **학습한 날:** 3/4"
        // 파일 없음 → 아직 없음
        let missing = await HomeSnapshot.make(paths: [], month: "2026-11", dailyPath: today) { _ in text }
        #expect(missing.daily(for: today) == nil)
        // 읽음
        let ok = await HomeSnapshot.make(paths: [today], month: "2026-11", dailyPath: today) { _ in text }
        #expect(ok.daily(for: today)?.today == 0.5)
        #expect(ok.daily(for: today)?.studyDays == 3)
        // 어제 값은 오늘처럼 보이지 않는다
        #expect(ok.daily(for: "Daily/2026-11/2026-11-13.md") == nil)
        // 읽기 실패: 지난 값 유지, 없으면 읽을 수 없음(0%가 아님)
        let kept = await HomeSnapshot.make(paths: [today], month: "2026-11", dailyPath: today, previous: ok) { _ in throw VaultError.unreadable }
        #expect(kept.daily(for: today) == ok.daily)
        let broken = await HomeSnapshot.make(paths: [today], month: "2026-11", dailyPath: today) { _ in throw VaultError.unreadable }
        #expect(broken.daily(for: today) == DailyProgress())
    }
}
