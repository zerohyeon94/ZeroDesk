import CryptoKit
import Foundation

/// 노트 하나의 Pencil 필기. md 파일은 건드리지 않고 볼트 숨김 폴더 `.zerodesk/필기/`에 따로 둔다.
/// 필기는 절마다 따로 저장한다. 그린 때의 절 내용(`hash`)과 글자 배치(`layout`)를 함께 적어 두고,
/// 지금과 다르면 필기 위치가 어긋났을 수 있다고 알린다.
public struct InkFile: Codable, Equatable, Sendable {
    public var version = 1
    public var sections: [String: SectionInk] = [:]

    public struct SectionInk: Codable, Equatable, Sendable {
        /// 그린 때의 절 내용 지문.
        public var hash: String
        /// 그린 때의 글자 배치(본문 폭·글자 크기).
        public var layout: String
        /// `PKDrawing.dataRepresentation()`.
        public var drawing: Data

        public init(hash: String, layout: String, drawing: Data) {
            self.hash = hash
            self.layout = layout
            self.drawing = drawing
        }
    }

    public init() {}

    public static let folder = ".zerodesk/필기"

    /// `Learning/개념/A.md` → `.zerodesk/필기/Learning/개념/A.md.ink.json`
    public static func path(for note: String) -> String { "\(folder)/\(note).ink.json" }

    /// 절의 필기가 지금 본문과 맞는지.
    public func matches(_ key: String, hash: String, layout: String) -> Bool {
        guard let s = sections[key] else { return true }
        return s.hash == hash && s.layout == layout
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> InkFile { try JSONDecoder().decode(InkFile.self, from: data) }
}

extension NoteDocument {
    /// 절마다 필기를 찾는 열쇠: 절 제목(머리 절은 ""). 같은 제목이 또 나오면 `#2`, `#3`을 붙인다.
    /// 앞에 절이 끼어들어도 번호가 아니라 제목으로 찾으므로 다른 절의 필기가 따라오지 않는다.
    public var inkKeys: [Int: String] {
        var seen: [String: Int] = [:]
        var out: [Int: String] = [:]
        for s in sections {
            let n = (seen[s.title] ?? 0) + 1
            seen[s.title] = n
            out[s.id] = n == 1 ? s.title : "\(s.title)#\(n)"
        }
        return out
    }
}

extension NoteSection {
    /// 절 내용 지문: 제목과 블록을 마크다운으로 다시 쓴 글의 SHA-256 앞 16자.
    public var inkHash: String {
        let text = title + "\n" + blocks.map { $0.format() }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
