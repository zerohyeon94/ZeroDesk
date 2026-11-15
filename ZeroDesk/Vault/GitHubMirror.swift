import Foundation

enum MirrorError: Error, Equatable {
    case badToken, notFound, rateLimited, truncated, offline, server(Int)

    var message: String {
        switch self {
        case .badToken: "토큰이 맞지 않거나 이 저장소를 읽을 권한이 없음"
        case .notFound: "저장소나 브랜치를 찾지 못함"
        case .rateLimited: "GitHub 호출 한도에 걸림. 잠시 뒤 다시 시도"
        case .truncated: "저장소 파일 목록이 너무 커서 한 번에 받지 못함"
        case .offline: "GitHub에 연결하지 못함"
        case let .server(code): "GitHub 응답 오류 (\(code))"
        }
    }
}

/// GitHub 저장소의 볼트를 앱 안 폴더(`root`)에 똑같이 받아 둔다. 읽기는 그 폴더를 `VaultAccess`가 한다.
///
/// 1. 파일 목록(`git/trees/<branch>?recursive=1`)을 ETag와 함께 부른다. 304면 바뀐 것 없음(호출 수에 안 셈).
/// 2. 받아 둔 버전(blob SHA)과 다른 `.md`·그림만 `git/blobs/<sha>`로 받는다.
/// 3. GitHub에서 사라진 파일은 지운다. `.`으로 시작하는 경로(`.zerodesk/` 필기 등)는 건드리지 않는다.
final class GitHubMirror: @unchecked Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    let root: URL
    let repo: String  // "owner/name"
    let branch: String
    private let token: String
    private let fetch: Fetch
    private var stateURL: URL { root.deletingLastPathComponent().appending(path: "github-mirror.json") }

    struct State: Codable, Equatable {
        var etag: String?
        var shas: [String: String] = [:]  // 경로 → blob SHA
    }

    init(root: URL, repo: String, branch: String = "main", token: String, fetch: Fetch? = nil) {
        self.root = root
        self.repo = repo
        self.branch = branch
        self.token = token
        self.fetch = fetch ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw MirrorError.offline }
            return (data, http)
        }
    }

    func loadState() -> State {
        (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    private func save(_ state: State) {
        try? JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    /// 받은 파일 수를 돌려준다. 바뀐 것이 없으면 0.
    @discardableResult
    func sync() async throws -> Int {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var state = loadState()
        var request = self.request("git/trees/\(branch)?recursive=1")
        if let etag = state.etag, !state.shas.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await call(request)
        if response.statusCode == 304 { return 0 }

        struct Tree: Decodable {
            struct Item: Decodable { let path: String; let type: String; let sha: String }
            let tree: [Item]
            let truncated: Bool
        }
        let tree = try JSONDecoder().decode(Tree.self, from: data)
        guard !tree.truncated else { throw MirrorError.truncated }
        let wanted = Dictionary(tree.tree.filter { $0.type == "blob" && Self.wants($0.path) }.map { ($0.path, $0.sha) },
                                uniquingKeysWith: { a, _ in a })

        for path in state.shas.keys where wanted[path] == nil {
            try? FileManager.default.removeItem(at: root.appending(path: path))
            state.shas[path] = nil
        }
        let changed = Array(wanted.filter { state.shas[$0.key] != $0.value })
        var done = 0
        var failure: Error?
        // 처음에는 파일이 많으므로 6개씩 동시에 받는다. 하나가 실패해도 나머지는 받고, 받은 만큼 저장한다.
        await withTaskGroup(of: (String, String, Error?).self) { group in
            var next = 0
            func addNext() {
                guard next < changed.count else { return }
                let (path, sha) = (changed[next].key, changed[next].value)
                next += 1
                group.addTask {
                    do { try await self.download(sha: sha, to: path); return (path, sha, nil) }
                    catch { return (path, sha, error) }
                }
            }
            for _ in 0..<6 { addNext() }
            while let (path, sha, error) = await group.next() {
                if let error { failure = failure ?? error } else { state.shas[path] = sha; done += 1 }
                addNext()
            }
        }
        // 실패가 있으면 ETag를 남기지 않아 다음에 목록을 다시 받고 빠진 것만 받는다
        state.etag = failure == nil ? response.value(forHTTPHeaderField: "ETag") : nil
        save(state)
        if let failure { throw failure }
        return done
    }

    /// 앱이 읽는 파일만: 숨김 경로·`..` 없이 `.md`와 그림.
    static func wants(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard !parts.isEmpty, !parts.contains(where: { $0.hasPrefix(".") }) else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md" || VaultAccess.imageExtensions.contains(ext)
    }

    private func download(sha: String, to path: String) async throws {
        var request = self.request("git/blobs/\(sha)")
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await call(request)
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func request(_ endpoint: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/\(endpoint)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData  // ETag는 직접 관리한다
        return request
    }

    private func call(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await fetch(request) } catch let error as MirrorError { throw error } catch {
            throw MirrorError.offline
        }
        switch response.statusCode {
        case 200, 304: return (data, response)
        case 401: throw MirrorError.badToken
        case 429: throw MirrorError.rateLimited
        case 403:
            if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" { throw MirrorError.rateLimited }
            throw MirrorError.badToken
        case 404: throw MirrorError.notFound  // 비공개 저장소는 권한이 없어도 404를 준다
        default: throw MirrorError.server(response.statusCode)
        }
    }
}

/// GitHub 토큰은 Keychain에만 둔다 (UserDefaults·스냅샷에 쓰지 않는다).
enum TokenStore {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.zerohyeon.zerodesk.github",
            kSecAttrAccount as String: "token",
        ]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}
