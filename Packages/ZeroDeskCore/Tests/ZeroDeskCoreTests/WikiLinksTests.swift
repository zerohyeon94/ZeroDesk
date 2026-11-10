import Foundation
import Testing
import ZeroDeskCore

/// 글에서 첫 링크(글, 주소)를 찾는다.
private func firstLink(_ markdown: String) -> (text: String, url: URL)? {
    func walk(_ m: Markup) -> (String, URL)? {
        if let l = m as? Link, let d = l.destination, let u = URL(string: d) { return (l.plainText, u) }
        for c in m.children { if let r = walk(c) { return r } }
        return nil
    }
    return walk(Document(parsing: markdown))
}

struct WikiLinksTests {
    @Test func stripsFrontmatter() {
        #expect(Frontmatter.strip("---\na: 1\n---\n# T") == "# T")
        #expect(Frontmatter.strip("# T\n---\n") == "# T\n---\n")
        #expect(Frontmatter.strip("---\n") == "---\n")
    }

    @Test func rewritesAliasAndHeading() throws {
        let out = WikiLinks.rewrite("[[Schedule/월별 목표 (2026-11 ~ 2027-10)#운영 방법|이번 달]]")
        let link = try #require(firstLink(out))
        #expect(link.text == "이번 달")
        let p = try #require(AppLink.parse(link.url))
        #expect(p.kind == "open")
        #expect(p.target == "Schedule/월별 목표 (2026-11 ~ 2027-10)")
        #expect(p.heading == "운영 방법")
    }

    @Test func defaultLabelIsLastPathPart() throws {
        let link = try #require(firstLink(WikiLinks.rewrite("[[Learning/개념/a b]]")))
        #expect(link.text == "a b")
        #expect(AppLink.parse(link.url)?.heading == nil)
    }

    @Test func escapedPipeInTable() throws {
        let out = WikiLinks.rewrite("| [[Schedule/x\\|보기]] | b |\n|---|---|\n| 1 | 2 |")
        #expect(firstLink(out)?.text == "보기")
        let table = try #require(Document(parsing: out).child(at: 0) as? Table)
        #expect(table.maxColumnCount == 2)
    }

    @Test func leavesCodeAlone() {
        let fenced = "```\n[[a]]\n```\n~~~\n[[c]]\n~~~"
        #expect(WikiLinks.rewrite(fenced) == fenced)
        #expect(WikiLinks.rewrite("x `[[b]]` y") == "x `[[b]]` y")
    }

    @Test func embedImage() throws {
        let out = WikiLinks.rewrite("![[Assets/2026-11-03 - 엣지-중앙 서버 구조.png]]")
        #expect(out.hasPrefix("![](zerodesk://asset?"))
        let img = try #require(Document(parsing: out).child(at: 0)?.child(at: 0) as? Image)
        #expect(AppLink.parse(URL(string: img.source!)!)?.target == "Assets/2026-11-03 - 엣지-중앙 서버 구조.png")
    }

    @Test func resolveExactPath() {
        #expect(VaultIndex(paths: ["Learning/개념/a.md", "Old/a.md"]).resolve("Learning/개념/a") == "Learning/개념/a.md")
    }

    @Test func resolveByNameShortest() {
        let i = VaultIndex(paths: ["Learning/개념/a.md", "Old/a.md"])
        #expect(i.resolve("a") == "Old/a.md")
        #expect(i.resolve("a.md") == "Old/a.md")
    }

    @Test func resolveAsset() {
        let i = VaultIndex(paths: ["Assets/p.png"])
        #expect(i.resolve("Assets/p.png") == "Assets/p.png")
        #expect(i.resolve("p.png") == "Assets/p.png")
    }

    @Test func resolveMissing() {
        #expect(VaultIndex(paths: ["Old/a.md"]).resolve("없는파일") == nil)
    }
}
