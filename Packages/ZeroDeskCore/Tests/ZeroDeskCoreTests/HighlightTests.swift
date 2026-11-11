import Foundation
import Testing
import ZeroDeskCore

struct HighlightTests {
    let para = "지점은 하루 일을 요약해서 본사(중앙 서버)에 보고한다. 본사는 요약해서 내려보낸다."

    private func range(of s: String, in p: String, occurrence: Int = 0) -> NSRange {
        let ns = p as NSString
        var r = ns.range(of: s)
        for _ in 0..<occurrence { r = ns.range(of: s, options: [], range: NSRange(location: NSMaxRange(r), length: ns.length - NSMaxRange(r))) }
        return r
    }

    @Test func makeTrimsSpacesAndKeepsContext() throws {
        var r = range(of: "요약해서", in: para)
        r.location -= 1; r.length += 2  // 앞뒤 공백까지 그음
        let h = try #require(Highlight.make(section: "비유", paragraph: para, range: r, color: .yellow))
        #expect(h.quote == "요약해서")
        #expect(h.prefix == "지점은 하루 일을 ")
        #expect(h.suffix.hasPrefix(" 본사(중앙"))
        #expect(Highlight.make(section: "비유", paragraph: para, range: NSRange(location: 3, length: 1), color: .yellow) == nil)
    }

    @Test func locatePicksRightOccurrence() throws {
        let second = range(of: "요약해서", in: para, occurrence: 1)
        let h = try #require(Highlight.make(section: "비유", paragraph: para, range: second, color: .green))
        #expect(h.locate(in: para) == second)
    }

    @Test func survivesEditsElsewhere() throws {
        let r = range(of: "요약해서", in: para)
        let h = try #require(Highlight.make(section: "비유", paragraph: para, range: r, color: .yellow))
        let edited = "새 문장. " + para
        #expect(h.locate(in: edited) == range(of: "요약해서", in: edited))
    }

    @Test func shortQuoteWithoutContextIsDropped() {
        let h = Highlight(section: "s", quote: "본사", prefix: "전혀 다른 앞", suffix: "전혀 다른 뒤", color: .yellow)
        #expect(h.locate(in: para) == nil)
        let long = Highlight(section: "s", quote: "본사(중앙 서버)에 보고", prefix: "x", suffix: "y", color: .yellow)
        #expect(long.locate(in: para) != nil)
    }

    @Test func resolvePicksOneParagraph() throws {
        let a = "새 업무 지침을 만들어 지점에 내려보낸다."
        let b = "엣지 장비는 본사가 내려보낸 프로그램으로만 움직인다."
        let h = try #require(Highlight.make(section: "비유", paragraph: a, range: (a as NSString).range(of: "내려보"), color: .yellow))
        let r = Highlight.resolve([h], paragraphs: [b, a])
        #expect(r[h.id]?.paragraph == 1)
        #expect(r[h.id]?.range == (a as NSString).range(of: "내려보"))
    }

    @Test func oneMatchingSpaceIsNotContext() {
        let h = Highlight(section: "s", quote: "내려보", prefix: "지점에 ", suffix: "았다.", color: .yellow)
        #expect(h.locate(in: "본사가 내려보낸 것") == nil)
    }

    @Test func memoIsOptionalAndRoundTrips() throws {
        let old = #"{"highlights":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","section":"비유","quote":"가","prefix":"","suffix":"","color":"yellow"}],"sections":{},"version":1}"#
        let f = try InkFile.decode(Data(old.utf8))
        #expect(f.highlights.first?.memo == nil)
        var g = f
        g.highlights[0].memo = HighlightMemo(text: "핵심", drawing: Data([7, 8]))
        #expect(try InkFile.decode(g.encoded()) == g)
    }

    @Test func emptyMemo() {
        #expect(HighlightMemo(text: "  \n").isEmpty)
        #expect(HighlightMemo(text: "", drawing: Data()).isEmpty)
        #expect(!HighlightMemo(text: "", drawing: Data([1])).isEmpty)
        #expect(!HighlightMemo(text: "a").isEmpty)
    }

    @Test func oldInkFileWithoutHighlightsDecodes() throws {
        let old = #"{"sections":{},"version":1}"#
        #expect(try InkFile.decode(Data(old.utf8)).highlights.isEmpty)
        var f = InkFile()
        f.highlights = [Highlight(section: "비유", quote: "가", prefix: "", suffix: "", color: .pink)]
        #expect(try InkFile.decode(f.encoded()) == f)
    }
}
