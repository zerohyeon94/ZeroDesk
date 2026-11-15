import Foundation
import Testing
@testable import ZeroDesk

struct InkStorageTests {
    let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    var old: URL { base.appending(path: "vault") }
    var new: URL { base.appending(path: "ink") }
    let access = VaultAccess(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

    private func put(_ text: String, _ rel: String, in root: URL) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ rel: String, in root: URL) -> String? {
        try? String(contentsOf: root.appending(path: rel), encoding: .utf8)
    }

    @Test func listsInkFilesOnlyWithICloudPlaceholdersByRealName() throws {
        try put("a", ".zerodesk/필기/Learning/개념/A.md.ink.json", in: old)
        try put("p", ".zerodesk/필기/Daily/.B.md.ink.json.icloud", in: old)
        try put("x", ".zerodesk/필기/메모.txt", in: old)
        try put("n", "Learning/개념/A.md", in: old)
        #expect(InkStorage.inkFiles(in: old) == [
            ".zerodesk/필기/Daily/B.md.ink.json",
            ".zerodesk/필기/Learning/개념/A.md.ink.json",
        ])
        #expect(InkStorage.inkFiles(in: base.appending(path: "없음")) == [])
    }

    @Test func migrateCopiesMissingKeepsNewerAndLeavesOld() async throws {
        let a = ".zerodesk/필기/A.md.ink.json", b = ".zerodesk/필기/B.md.ink.json"
        try put("old a", a, in: old)
        try put("old b", b, in: old)
        try put("new b", b, in: new)  // 새 위치에서 이미 고친 필기는 덮어쓰지 않는다
        #expect(await InkStorage.migrate(from: [old], to: new, access: access) == 1)
        #expect(read(a, in: new) == "old a")
        #expect(read(b, in: new) == "new b")
        #expect(read(a, in: old) == "old a")  // 예전 것은 지우지 않는다
        // 다시 불러도 아무것도 하지 않는다
        #expect(await InkStorage.migrate(from: [old], to: new, access: access) == 0)
    }

    @Test func migrateSkipsSameFolderAndMissingSources() async throws {
        try put("a", ".zerodesk/필기/A.md.ink.json", in: new)
        #expect(await InkStorage.migrate(from: [new, base.appending(path: "없음")], to: new, access: access) == 0)
    }
}
