import PencilKit
import SwiftUI
import ZeroDeskCore

/// 형광펜에 단 메모를 쓰고 고치는 창. 키보드 글과 Pencil 손글씨를 함께 쓸 수 있다.
/// 닫을 때 저장하고, 글도 손글씨도 없으면 메모를 없앤다.
struct MemoSheet: View {
    let highlight: Highlight
    let ink: NoteInk
    /// 형광펜(과 메모)을 지운다.
    let removeHighlight: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var drawing: Data?
    @State private var erasing = false
    @AppStorage("pen.color") private var penColor: PenColor = .black
    @State private var confirm: Confirm?
    @State private var discarded = false

    enum Confirm: Identifiable {
        case memo, highlight
        var id: Self { self }
    }

    init(highlight: Highlight, ink: NoteInk, removeHighlight: @escaping (UUID) -> Void) {
        self.highlight = highlight
        self.ink = ink
        self.removeHighlight = removeHighlight
        _text = State(initialValue: highlight.memo?.text ?? "")
        _drawing = State(initialValue: highlight.memo?.drawing)
    }

    private var memo: HighlightMemo { HighlightMemo(text: text, drawing: drawing) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(highlight.quote)
                        .font(.callout)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(highlight.color.swatch.opacity(0.3), in: .rect(cornerRadius: 4))
                        .lineLimit(3)
                    TextField("메모 입력", text: $text, axis: .vertical)
                        .lineLimit(2...8)
                        .padding(10)
                        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 14) {
                            Text("손글씨 (Pencil)").font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            // Apple 기본 도구 막대 대신: 펜 색 셋 + 지우개
                            ForEach(PenColor.allCases, id: \.self) { c in
                                Button { penColor = c; erasing = false } label: {
                                    Circle().fill(c.swatch).frame(width: 22, height: 22)
                                        .overlay(Circle().stroke(.primary.opacity(!erasing && penColor == c ? 0.8 : 0), lineWidth: 2).padding(-4))
                                }
                                .accessibilityLabel("펜 \(c.label)")
                            }
                            Button { erasing.toggle() } label: {
                                Image(systemName: "eraser").symbolVariant(erasing ? .fill : .none)
                                    .foregroundStyle(erasing ? AnyShapeStyle(.pink) : AnyShapeStyle(.secondary))
                            }
                            .accessibilityLabel(erasing ? "지우개 끝내기" : "지우개")
                        }
                        .buttonStyle(.plain)
                        InkCanvas(data: drawing, mode: erasing ? .erase : .pen(penColor), stale: false) { d, bytes in
                            drawing = d.strokes.isEmpty ? nil : bytes
                        }
                        .frame(height: 280)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                    }
                    HStack {
                        Button("메모 지우기", role: .destructive) { confirm = .memo }
                            .disabled(memo.isEmpty && highlight.memo == nil)
                        Spacer()
                        Button("형광펜 지우기", role: .destructive) { confirm = .highlight }
                    }
                    .font(.callout)
                }
                .padding(20)
            }
            .navigationTitle("메모")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
            .confirmationDialog(confirm == .memo ? "메모를 지울까요?" : "형광펜과 메모를 지울까요?",
                                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                                titleVisibility: .visible, presenting: confirm) { c in
                Button(c == .memo ? "메모 지우기" : "형광펜 지우기", role: .destructive) {
                    discarded = true
                    if c == .memo { ink.setMemo(nil, for: highlight.id) } else { removeHighlight(highlight.id) }
                    dismiss()
                }
            } message: { _ in Text("지운 뒤에는 되돌릴 수 없습니다.") }
            .onDisappear {
                guard !discarded else { return }
                let m = memo
                if m != (highlight.memo ?? HighlightMemo()) { ink.setMemo(m.isEmpty ? nil : m, for: highlight.id) }
            }
        }
    }
}
