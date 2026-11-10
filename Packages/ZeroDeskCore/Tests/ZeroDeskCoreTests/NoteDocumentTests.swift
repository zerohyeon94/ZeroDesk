import Foundation
import Testing
import ZeroDeskCore

struct NoteDocumentTests {
    let concept = "Learning/개념/2026-11-03 엣지-중앙 서버 구조.md"

    @Test func conceptFixtureSections() throws {
        let d = NoteDocument.parse(try fixture(concept))
        #expect(d.title == "엣지-중앙 서버 구조")
        #expect(d.sections.filter { !$0.title.isEmpty }.map(\.title)
                == ["한 문장으로", "비유", "흐름", "어디서 깨지나", "이런 시스템에서는", "단어 정리"])
        #expect(d.sections.map(\.id) == Array(0..<d.sections.count))
        #expect(d.sections[0].title == "" && d.sections[0].blocks.count == 1)  // 머리 인용
    }

    @Test func headingLookup() throws {
        let d = NoteDocument.parse(try fixture(concept))
        let flow = try #require(d.sections.first { $0.title == "흐름" })
        #expect(d.sectionIndex(forHeading: "4) 네트워크가 끊겼다가 돌아올 때") == flow.id)
        #expect(d.sectionIndex(forHeading: "비유") == d.sections.first { $0.title == "비유" }?.id)
        #expect(d.sectionIndex(forHeading: "없는 제목") == nil)
    }

    @Test func noSections() {
        let d = NoteDocument.parse("그냥 글")
        #expect(d.sections.count == 1)
        #expect(d.title == nil)
    }

    @Test func emptyFile() {
        let d = NoteDocument.parse("")
        #expect(d.sections.count == 1)
        #expect(d.sections[0].blocks.isEmpty)
    }

    @Test func frontmatterOnly() {
        #expect(NoteDocument.parse("---\na: 1\n---\n").sections.allSatisfy { $0.blocks.isEmpty })
    }

    @Test func linksRewritten() {
        let d = NoteDocument.parse("## A\n[[x]]")
        #expect(d.sections[1].blocks.first?.format().contains("zerodesk://open") == true)
    }

    @Test func layoutForPath() {
        #expect(NoteLayout.forPath("Schedule/학습 대기열.md") == .queue)
        #expect(NoteLayout.forPath("Daily/2026-11/2026-11-09.md") == .daily)
        #expect(NoteLayout.forPath("Learning/개념/x.md") == .longRead)
    }
}
