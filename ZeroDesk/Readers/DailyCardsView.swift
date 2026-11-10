import SwiftUI
import ZeroDeskCore

/// Daily: `##` 절마다 카드, 넓은 화면(≥ 900pt)에서는 2열 (스펙 5.2).
struct DailyCardsView: View {
    let doc: NoteDocument
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let title = doc.title { Text(title).font(.largeTitle.bold()) }
                if let head = doc.sections.first, !head.blocks.isEmpty { BlocksView(blocks: head.blocks) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: width >= 900 ? 2 : 1),
                          alignment: .leading, spacing: 16) {
                    ForEach(doc.sections.dropFirst()) { s in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(s.title).font(.headline)
                            BlocksView(blocks: s.blocks)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.2)))
                    }
                }
            }
            .padding(20)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
