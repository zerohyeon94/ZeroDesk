import Foundation
import Observation
import ZeroDeskCore

/// 홈이 보여 줄 숫자. 앱을 켤 때 지난 값으로 먼저 보여 준다 (스펙 8 빠른 시작).
struct HomeSnapshot: Codable, Equatable {
    var month: QueueMonth?
    var monthSectionMissing: Bool
    var queueUnreadable: Bool
    var yearGoal: String?
    var schedule: ScheduleFile?
    var scheduleMissing: Bool

    static let queuePath = "Schedule/학습 대기열.md"
    static let schedulePath = "Schedule/주요 일정.md"

    /// 대기열·월별 목표·주요 일정 세 파일만 읽어 홈 숫자를 만든다.
    static func make(paths: [String], month: String, read: @Sendable (String) async throws -> String) async -> HomeSnapshot {
        var s = HomeSnapshot(month: nil, monthSectionMissing: false, queueUnreadable: false,
                             yearGoal: nil, schedule: nil, scheduleMissing: !paths.contains(schedulePath))
        if paths.contains(queuePath), let text = try? await read(queuePath) {
            s.month = QueueProgress.parse(text, month: month)
            s.monthSectionMissing = s.month == nil
            if s.month?.total == 0 { s.queueUnreadable = true }
        } else {
            s.queueUnreadable = true
        }
        if let goal = paths.filter({ $0.hasPrefix("Schedule/월별 목표 (") }).max(),
           let text = try? await read(goal) {
            s.yearGoal = YearGoal.line(in: text)
        }
        if !s.scheduleMissing {
            if let text = try? await read(schedulePath) { s.schedule = ScheduleFile.parse(text) } else { s.scheduleMissing = true }
        }
        return s
    }
}

private struct Snapshot: Codable {
    var files: [VaultFileInfo]
    var home: HomeSnapshot?
}

/// KST 오늘 날짜.
func todayKST(_ now: Date = .now) -> DateComponents { kstCalendar.dateComponents([.year, .month, .day], from: now) }
let kstCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
}()

@Observable @MainActor
final class VaultStore {
    enum Phase: Equatable { case needsFolder, loading, ready, failed(String) }

    var phase: Phase = .loading
    var files: [VaultFileInfo] = []
    var index = VaultIndex(paths: [])
    var home: HomeSnapshot?
    var lastRefresh: Date?

    @ObservationIgnored let access: VaultAccess
    @ObservationIgnored private(set) var root: URL?
    @ObservationIgnored private var refreshing = false

    init(access: VaultAccess = .init()) { self.access = access }

    private var snapshotURL: URL {
        URL.applicationSupportDirectory.appending(path: "snapshot.json")
    }

    func start() async {
        if let data = try? Data(contentsOf: snapshotURL), let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            apply(files: snap.files)
            home = snap.home
            phase = .ready
        }
        #if DEBUG
        // 시뮬레이터 확인용: -vaultPath <경로>
        if let p = UserDefaults.standard.string(forKey: "vaultPath") { root = URL(filePath: p) }
        #endif
        if root == nil {
            do { root = try access.restore() } catch {
                phase = .needsFolder
                return
            }
        }
        await refresh()
    }

    func pick(folder: URL) async {
        do {
            try access.save(folder: folder)
            root = try access.restore()
            phase = .loading
            await refresh()
        } catch {
            phase = .needsFolder
        }
    }

    func refresh() async {
        guard let root else { phase = .needsFolder; return }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let access = access
        do {
            let list = try await Task.detached { try access.listFiles(in: root) }.value
            apply(files: list)
            let t = todayKST()
            let month = String(format: "%04d-%02d", t.year ?? 0, t.month ?? 0)
            home = await HomeSnapshot.make(paths: list.map(\.path), month: month) { path in
                try await access.readText(path, root: root)
            }
            phase = .ready
            lastRefresh = .now
            try? FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(Snapshot(files: list, home: home)).write(to: snapshotURL)
        } catch VaultError.accessLost, VaultError.noFolder {
            phase = .needsFolder
        } catch {
            if home == nil { phase = .failed("볼트를 읽지 못함") }
        }
    }

    private func apply(files list: [VaultFileInfo]) {
        files = list
        index = VaultIndex(paths: list.map(\.path))
    }

    func text(of path: String) async throws -> String {
        guard let root else { throw VaultError.noFolder }
        return try await access.readText(path, root: root)
    }

    func data(of path: String) async throws -> Data {
        guard let root else { throw VaultError.noFolder }
        return try await access.readData(path, root: root)
    }

    func fileURL(_ path: String) -> URL? { root.map { access.fileURL(path, root: $0) } }

    func lastSection(of path: String) -> Int { access.defaults.integer(forKey: "lastSection." + path) }
    func setLastSection(_ i: Int, of path: String) { access.defaults.set(i, forKey: "lastSection." + path) }
}
