import Foundation

public enum Frontmatter {
    /// 맨 앞 `---\n…\n---\n` 앞머리만 지운다 (스펙 5.4).
    public static func strip(_ text: String) -> String {
        guard text.hasPrefix("---\n"),
              let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex)
        else {
            // 파일 끝에서 닫히는 앞머리 ("---\n…\n---")
            if text.hasPrefix("---\n"), text.hasSuffix("\n---"), text.count > 7 { return "" }
            return text
        }
        return String(text[end.upperBound...])
    }
}

/// 앱 안 링크: `zerodesk://open?t=&h=`, `zerodesk://asset?t=` (스펙 6).
public enum AppLink {
    public static let scheme = "zerodesk"

    public static func open(_ target: String, heading: String? = nil) -> URL {
        var s = "\(scheme)://open?t=\(encode(target))"
        if let heading { s += "&h=\(encode(heading))" }
        return URL(string: s)!
    }

    public static func asset(_ target: String) -> URL { URL(string: "\(scheme)://asset?t=\(encode(target))")! }

    public static func parse(_ url: URL) -> (kind: String, target: String, heading: String?)? {
        guard url.scheme == scheme, let host = url.host(),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let t = items.first(where: { $0.name == "t" })?.value else { return nil }
        return (host, t, items.first { $0.name == "h" }?.value)
    }

    /// 괄호·공백까지 모두 인코딩해 마크다운 링크 주소 안에서 깨지지 않게 한다.
    private static let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
    private static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: safe)! }
}

public enum WikiLinks {
    nonisolated(unsafe) private static let pattern = /(!?)\[\[([^\[\]\n]+?)\]\]/

    /// 코드 밖의 `[[t#h|label]]`를 마크다운 링크로, `![[t]]`를 그림으로 바꾼다.
    public static func rewrite(_ markdown: String) -> String {
        var fence: String?
        return markdown.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let f = fence {
                if trimmed.hasPrefix(f) { fence = nil }
                return line
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                return line
            }
            // 백틱으로 나눈 조각 중 짝수 번째만 코드 밖이다.
            return line.split(separator: "`", omittingEmptySubsequences: false).enumerated()
                .map { $0.offset.isMultiple(of: 2) ? rewriteSpan(String($0.element)) : String($0.element) }
                .joined(separator: "`")
        }.joined(separator: "\n")
    }

    static func rewriteSpan(_ s: String) -> String {
        s.replacing(pattern) { m in
            let inner = String(m.output.2).replacingOccurrences(of: "\\|", with: "|")
            let bar = inner.firstIndex(of: "|")
            let ref = bar.map { String(inner[..<$0]) } ?? inner
            let label = bar.map { String(inner[inner.index(after: $0)...]) }
            let hash = ref.firstIndex(of: "#")
            let target = (hash.map { String(ref[..<$0]) } ?? ref).trimmingCharacters(in: .whitespaces)
            let heading = hash.map { String(ref[ref.index(after: $0)...]).trimmingCharacters(in: .whitespaces) }
            if !m.output.1.isEmpty { return "![](\(AppLink.asset(target).absoluteString))" }
            let text = label ?? (target.isEmpty ? heading ?? "" : String(target.split(separator: "/").last ?? ""))
            let escaped = text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            return "[\(escaped)](\(AppLink.open(target, heading: heading).absoluteString))"
        }
    }
}

/// 볼트 파일 경로 색인. 경로는 볼트 기준 상대 경로.
public struct VaultIndex: Codable, Equatable, Sendable {
    public var paths: [String]
    private var set: Set<String>

    public init(paths: [String]) {
        self.paths = paths
        self.set = Set(paths)
    }

    /// 정확한 경로(`.md` 생략 허용) → 파일 이름이 같은 것 중 경로가 가장 짧은 것.
    public func resolve(_ target: String) -> String? {
        let t = target.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if set.contains(t) { return t }
        if set.contains(t + ".md") { return t + ".md" }
        let name = String(t.split(separator: "/").last ?? "")
        return paths.filter {
            let last = $0.split(separator: "/").last.map(String.init) ?? $0
            return last == name || last == name + ".md"
        }.min { ($0.count, $0) < ($1.count, $1) }
    }
}
