import Foundation

enum VaultError: Error, Equatable {
    case noFolder, accessLost, notDownloaded, unreadable
}

struct VaultFileInfo: Codable, Hashable, Sendable {
    var path: String
    var modified: Date
}

/// 볼트 폴더 접근: 북마크 저장·복원, 파일 목록, iCloud 내려받기 + 조정 읽기 (스펙 8).
/// 볼트에는 절대 쓰지 않는다.
// UserDefaults와 FileManager는 스레드 안전하다.
final class VaultAccess: @unchecked Sendable {
    let defaults: UserDefaults
    private let bookmarkKey = "vaultBookmark"
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg"]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// 폴더 고르기 창에서 받은 URL의 접근 권한을 북마크로 저장한다.
    func save(folder: URL) throws {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        do {
            defaults.set(try folder.bookmarkData(), forKey: bookmarkKey)
        } catch { throw VaultError.accessLost }
    }

    /// 저장한 북마크로 폴더를 다시 연다. 접근은 앱이 끝날 때까지 유지한다.
    func restore() throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else { throw VaultError.noFolder }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { throw VaultError.accessLost }
        _ = url.startAccessingSecurityScopedResource()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw VaultError.accessLost
        }
        if stale { try? save(folder: url) }
        return url
    }

    /// `.md`와 그림 파일만, 숨김 폴더·파일 제외, 경로순. 아직 안 내려온 iCloud 자리표시(`.x.md.icloud`)는 진짜 이름으로 센다.
    func listFiles(in root: URL) throws -> [VaultFileInfo] {
        let base = root.resolvingSymlinksInPath().path + "/"
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants])
        else { throw VaultError.accessLost }
        var out: [VaultFileInfo] = []
        for case let url as URL in e {
            let values = try? url.resourceValues(forKeys: Set(keys))
            var name = url.lastPathComponent
            if values?.isDirectory == true {
                if name.hasPrefix(".") { e.skipDescendants() }
                continue
            }
            if name.hasPrefix(".") {
                guard name.hasSuffix(".icloud") else { continue }
                name = String(name.dropFirst().dropLast(".icloud".count))
            }
            guard name.hasSuffix(".md") || Self.imageExtensions.contains((name as NSString).pathExtension.lowercased()) else { continue }
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().path + "/" + name
            guard full.hasPrefix(base) else { continue }
            out.append(VaultFileInfo(path: String(full.dropFirst(base.count)), modified: values?.contentModificationDate ?? .distantPast))
        }
        return out.sorted { $0.path < $1.path }
    }

    func fileURL(_ relPath: String, root: URL) -> URL { root.appending(path: relPath) }

    /// iCloud에 아직 없으면 내려받기를 요청하고 기다린 뒤, 조정 읽기로 글을 읽는다.
    func readText(_ relPath: String, root: URL, timeout: Duration = .seconds(30)) async throws -> String {
        guard let s = String(data: try await readData(relPath, root: root, timeout: timeout), encoding: .utf8) else {
            throw VaultError.unreadable
        }
        return s
    }

    /// 그림처럼 글이 아닌 파일도 같은 방식(내려받기 + 조정 읽기)으로 읽는다.
    func readData(_ relPath: String, root: URL, timeout: Duration = .seconds(30)) async throws -> Data {
        let url = fileURL(relPath, root: root)
        try await ensureDownloaded(url, timeout: timeout)
        var coordError: NSError?
        var result: Result<Data, VaultError> = .failure(.unreadable)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            if let d = try? Data(contentsOf: u) { result = .success(d) }
        }
        return try result.get()
    }

    private func ensureDownloaded(_ url: URL, timeout: Duration) async throws {
        func status() -> URLUbiquitousItemDownloadingStatus? {
            var u = url
            u.removeAllCachedResourceValues()
            let v = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard v?.isUbiquitousItem == true else { return nil }
            return v?.ubiquitousItemDownloadingStatus
        }
        guard let s = status(), s != .current else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            try await Task.sleep(for: .milliseconds(300))
            if status() == .current { return }
        }
        throw VaultError.notDownloaded
    }
}
