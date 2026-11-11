import Foundation
import Testing
import ZeroDeskCore

struct InkFileTests {
    @Test func pathIsHidden() {
        #expect(InkFile.path(for: "Learning/개념/A.md") == ".zerodesk/필기/Learning/개념/A.md.ink.json")
    }

    @Test func keysUseTitlesAndNumberRepeats() {
        let d = NoteDocument.parse("머리\n\n## 비유\n가\n\n## 흐름\n나\n\n## 비유\n다\n")
        #expect(d.inkKeys == [0: "", 1: "비유", 2: "흐름", 3: "비유#2"])
    }

    @Test func insertingSectionKeepsOtherKeysAndHashes() {
        let a = NoteDocument.parse("## 비유\n가\n\n## 흐름\n나\n")
        let b = NoteDocument.parse("## 새 절\n추가\n\n## 비유\n가\n\n## 흐름\n나\n")
        let flowA = a.sections.first { $0.title == "흐름" }!
        let flowB = b.sections.first { $0.title == "흐름" }!
        #expect(a.inkKeys[flowA.id] == b.inkKeys[flowB.id])
        #expect(flowA.inkHash == flowB.inkHash)
    }

    @Test func editingSectionChangesHash() {
        let a = NoteDocument.parse("## 비유\n가\n").sections[1]
        let b = NoteDocument.parse("## 비유\n가나\n").sections[1]
        #expect(a.inkHash != b.inkHash)
        #expect(a.inkHash.count == 16)
    }

    @Test func matchesAndRoundTrip() throws {
        var f = InkFile()
        f.sections["비유"] = .init(hash: "h1", layout: "680|large", drawing: Data([1, 2, 3]))
        #expect(f.matches("비유", hash: "h1", layout: "680|large"))
        #expect(!f.matches("비유", hash: "h2", layout: "680|large"))
        #expect(!f.matches("비유", hash: "h1", layout: "680|xLarge"))
        #expect(f.matches("없는 절", hash: "x", layout: "y"))
        #expect(try InkFile.decode(f.encoded()) == f)
    }
}
