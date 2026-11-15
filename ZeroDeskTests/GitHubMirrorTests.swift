import Foundation
import Testing
@testable import ZeroDesk

/// 가짜 GitHub: 파일 목록과 blob을 돌려주고 받은 요청을 기록한다.
private final class FakeGitHub: @unchecked Sendable {
    private let lock = NSLock()
    var tree: [(path: String, sha: String)] = []
    var blobs: [String: String] = [:]  // sha → 내용
    var etag = "\"v1\""
    var failBlob: String?
    var status = 200
    private(set) var requests: [URLRequest] = []

    func handle(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        let url = request.url!
        func reply(_ code: Int, _ data: Data = Data(), headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
            (data, HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: headers)!)
        }
        if status != 200 { return reply(status) }
        if url.path.contains("/git/trees/") {
            if request.value(forHTTPHeaderField: "If-None-Match") == etag { return reply(304) }
            let items = tree.map { ["path": $0.path, "type": "blob", "sha": $0.sha] } + [["path": "Daily", "type": "tree", "sha": "t"]]
            let body = try JSONSerialization.data(withJSONObject: ["tree": items, "truncated": false])
            return reply(200, body, headers: ["ETag": etag])
        }
        let sha = url.lastPathComponent
        if sha == failBlob { throw URLError(.notConnectedToInternet) }
        return reply(200, Data((blobs[sha] ?? "").utf8))
    }

    var blobCalls: Int { lock.lock(); defer { lock.unlock() }; return requests.filter { $0.url!.path.contains("/git/blobs/") }.count }
}

struct GitHubMirrorTests {
    let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    var root: URL { base.appending(path: "vault") }
    private let github = FakeGitHub()

    private func mirror() -> GitHubMirror {
        let github = github
        return GitHubMirror(root: root, repo: "o/r", token: "t") { try github.handle($0) }
    }

    private func read(_ path: String) -> String? { try? String(contentsOf: root.appending(path: path), encoding: .utf8) }

    @Test func firstSyncDownloadsOnlyReadableFiles() async throws {
        github.tree = [("Daily/a.md", "s1"), ("Assets/b.png", "s2"), (".obsidian/c.json", "s3"), ("x.txt", "s4"), (".h/d.md", "s5")]
        github.blobs = ["s1": "가", "s2": "png"]
        #expect(try await mirror().sync() == 2)
        #expect(read("Daily/a.md") == "가")
        #expect(read("Assets/b.png") == "png")
        #expect(read("x.txt") == nil && read(".h/d.md") == nil)
        #expect(github.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test func unchangedTreeIsNotModifiedAndDownloadsNothing() async throws {
        github.tree = [("a.md", "s1")]
        github.blobs = ["s1": "x"]
        try await mirror().sync()
        #expect(try await mirror().sync() == 0)
        #expect(github.blobCalls == 1)
        #expect(github.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    }

    @Test func changedAndRemovedFilesFollowGitHubButInkStays() async throws {
        github.tree = [("a.md", "s1"), ("b.md", "s2")]
        github.blobs = ["s1": "old", "s2": "b", "s3": "new"]
        try await mirror().sync()
        try FileManager.default.createDirectory(at: root.appending(path: ".zerodesk"), withIntermediateDirectories: true)
        try Data("ink".utf8).write(to: root.appending(path: ".zerodesk/n.ink.json"))

        github.tree = [("a.md", "s3")]
        github.etag = "\"v2\""
        #expect(try await mirror().sync() == 1)
        #expect(read("a.md") == "new")
        #expect(read("b.md") == nil)
        #expect(read(".zerodesk/n.ink.json") == "ink")
    }

    @Test func failedDownloadKeepsProgressAndRetriesRest() async throws {
        github.tree = [("a.md", "s1"), ("b.md", "s2")]
        github.blobs = ["s1": "a", "s2": "b"]
        github.failBlob = "s2"
        await #expect(throws: MirrorError.offline) { try await mirror().sync() }
        #expect(mirror().loadState().etag == nil)  // 목록을 다시 받게 한다

        github.failBlob = nil
        #expect(try await mirror().sync() == 1)  // a.md는 다시 받지 않는다
        #expect(read("b.md") == "b")
    }

    @Test func authAndRateLimitErrors() async throws {
        github.status = 401
        await #expect(throws: MirrorError.badToken) { try await mirror().sync() }
        github.status = 404
        await #expect(throws: MirrorError.notFound) { try await mirror().sync() }
        github.status = 429
        await #expect(throws: MirrorError.rateLimited) { try await mirror().sync() }
    }

    @Test func wantsRejectsHiddenAndParentPaths() {
        #expect(GitHubMirror.wants("Learning/개념/a.md"))
        #expect(GitHubMirror.wants("Assets/a.PNG"))
        #expect(!GitHubMirror.wants("../a.md"))
        #expect(!GitHubMirror.wants("a/../../b.md"))
        #expect(!GitHubMirror.wants(".zerodesk/a.md"))
        #expect(!GitHubMirror.wants("a.json"))
    }
}
