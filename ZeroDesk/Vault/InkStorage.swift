import Foundation
import ZeroDeskCore

/// 필기를 두는 곳: 앱 전용 iCloud 공간. 볼트(iCloud 폴더·GitHub 사본)와 분리해 기기끼리 동기화한다.
/// 경로는 볼트 때와 같은 `.zerodesk/필기/<노트 경로>.ink.json`이고, 읽기·쓰기는 `VaultAccess`가 한다.
enum InkStorage {
    static let containerID = "iCloud.com.zerohyeon.zerodesk"
    static let localRoot = URL.applicationSupportDirectory.appending(path: "ink")

    /// 앱 전용 iCloud 공간의 Documents. iCloud를 쓸 수 없으면(로그인 안 함·시뮬레이터) 기기 안 폴더.
    /// 처음 부를 때 오래 걸릴 수 있어 메인 스레드에서 부르지 않는다.
    static func root() -> URL {
        FileManager.default.url(forUbiquityContainerIdentifier: containerID)?.appending(path: "Documents") ?? localRoot
    }

    /// 예전 위치들의 필기를 새 위치로 복사한다. 새 위치에 이미 있으면 그대로 두고, 예전 것은 지우지 않는다.
    /// 못 읽은 파일은 건너뛰고 다음 실행에 다시 시도한다. 복사한 수를 돌려준다.
    @discardableResult
    static func migrate(from olds: [URL], to new: URL, access: VaultAccess) async -> Int {
        var copied = 0
        for old in olds where old.standardizedFileURL != new.standardizedFileURL {
            for rel in inkFiles(in: old) where !access.exists(rel, root: new) {
                guard let data = try? await access.readData(rel, root: old),
                      (try? access.writeData(data, to: rel, root: new)) != nil else { continue }
                copied += 1
            }
        }
        return copied
    }

    /// `root/.zerodesk/필기/` 아래 필기 파일의 볼트 기준 경로. 아직 안 내려온 iCloud 자리표시는 진짜 이름으로.
    static func inkFiles(in root: URL) -> [String] {
        let base = root.appending(path: InkFile.folder)
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        let prefix = base.resolvingSymlinksInPath().path + "/"
        var out: [String] = []
        for case let url as URL in e where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
            var name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(".icloud".count)) }
            guard name.hasSuffix(".ink.json") else { continue }
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().path + "/" + name
            guard full.hasPrefix(prefix) else { continue }
            out.append(InkFile.folder + "/" + full.dropFirst(prefix.count))
        }
        return out.sorted()
    }
}
