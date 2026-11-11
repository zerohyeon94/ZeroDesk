import SwiftUI
import Testing
import UIKit
@testable import ZeroDesk

@MainActor
struct MonoGridTests {
    /// 자간을 넣은 뒤 그려지는 폭을 잰다.
    private func drawnWidth(_ s: String) -> CGFloat {
        let font = MonoGrid.font
        let a = NSMutableAttributedString()
        for run in MonoGrid.text(s, font: font).runs {
            let piece = String(MonoGrid.text(s, font: font)[run.range].characters)
            a.append(NSAttributedString(string: piece, attributes: [.font: font, .kern: run.kern ?? 0]))
        }
        return a.size().width
    }

    @Test func hangulIsTwoCells() {
        let cell = MonoGrid.cell()
        // 자간 없이 그리면 한글이 2칸에 맞지 않는다 (고칠 문제가 실제로 있음)
        #expect(abs(MonoGrid.width("가", MonoGrid.font) - cell * 2) > 0.5)
        // 칸을 좁혀 한글 사이 틈이 글자 폭의 25%를 넘지 않는다 (`카 메 라`처럼 벌어지지 않음)
        #expect(cell * 2 - MonoGrid.width("가", MonoGrid.font) < MonoGrid.width("가", MonoGrid.font) * 0.25)
        #expect(abs(drawnWidth("가나다") - cell * 6) < 0.5)
        #expect(abs(drawnWidth("ab") - cell * 2) < 0.5)
        #expect(abs(drawnWidth("│ 엣지 ─") - cell * 8) < 0.5)
    }

    @Test func wideRanges() {
        #expect(MonoGrid.isWide("한"))
        #expect(MonoGrid.isWide("漢"))
        #expect(!MonoGrid.isWide("a"))
        #expect(!MonoGrid.isWide("─"))
    }
}
