import PencilKit
import SwiftUI

/// 필기 층에서 쓰는 도구. Apple 기본 도구 막대 대신 앱이 직접 고른다.
enum InkMode: Equatable {
    /// 보기만: 손을 대지 않는다 (링크 누르기·스크롤·형광펜은 아래 본문이 받는다).
    case view
    case pen(PenColor)
    case erase
}

/// 펜 색. 검정은 어두운 화면에서 PencilKit이 흰색으로 바꿔 보여 준다.
enum PenColor: String, CaseIterable {
    case black, blue, red

    var label: String {
        switch self {
        case .black: "검정"
        case .blue: "파랑"
        case .red: "빨강"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .black: .black
        case .blue: .systemBlue
        case .red: .systemRed
        }
    }

    var swatch: Color { Color(uiColor: self == .black ? .label : uiColor) }
}

/// 절 하나(또는 메모 창) 위에 얹는 투명한 필기 층.
/// 펜·지우개일 때만 Pencil 입력을 받고, 손가락으로는 그대로 스크롤한다.
struct InkCanvas: UIViewRepresentable {
    /// 저장된 필기 (`PKDrawing.dataRepresentation()`). 밖에서 바뀔 때만 다시 그린다.
    let data: Data?
    let mode: InkMode
    /// 본문이 바뀌어 위치가 어긋났을 수 있는 필기: 흐리게, 고칠 수 없게.
    let stale: Bool
    var lineWidth: CGFloat = 2.5
    let onChange: (PKDrawing, Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> InkCanvasView {
        let v = InkCanvasView(frame: .zero)
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isScrollEnabled = false
        v.contentInsetAdjustmentBehavior = .never
        #if targetEnvironment(simulator)
        v.drawingPolicy = .anyInput  // 시뮬레이터에는 Pencil이 없다
        #else
        v.drawingPolicy = .pencilOnly
        #endif
        context.coordinator.apply(data, to: v)
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v: InkCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        if data != context.coordinator.lastData, !context.coordinator.drawingInProgress {
            context.coordinator.apply(data, to: v)
        }
        let m = stale ? .view : mode
        v.isUserInteractionEnabled = m != .view
        v.erasing = m == .erase
        v.alpha = stale ? 0.35 : 1
        switch m {
        case .pen(let c): v.tool = PKInkingTool(.pen, color: c.uiColor, width: lineWidth)
        case .erase: v.tool = PKEraserTool(.vector)  // 닿은 획 하나를 통째로 지움
        case .view: break
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onChange: (PKDrawing, Data) -> Void
        var applying = false
        var drawingInProgress = false
        /// 캔버스에 있는 필기의 데이터. 모델이 같은 값을 돌려주면 다시 그리지 않는다.
        var lastData: Data?

        init(onChange: @escaping (PKDrawing, Data) -> Void) { self.onChange = onChange }

        func apply(_ data: Data?, to v: PKCanvasView) {
            applying = true
            v.drawing = data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
            applying = false
            lastData = data
        }

        func canvasViewDidBeginUsingTool(_ v: PKCanvasView) {
            drawingInProgress = true
        }

        func canvasViewDidEndUsingTool(_ v: PKCanvasView) { drawingInProgress = false }

        func canvasViewDrawingDidChange(_ v: PKCanvasView) {
            guard !applying else { return }
            let d = v.drawing.strokes.isEmpty ? nil : v.drawing.dataRepresentation()
            lastData = d
            onChange(v.drawing, d ?? Data())
        }
    }
}

/// 지우개일 때는 획이 있는 곳만 받고, 빈 곳 누르기는 아래 본문으로 넘긴다 (본문의 형광펜을 지우도록).
final class InkCanvasView: PKCanvasView {
    var erasing = false

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard erasing else { return super.point(inside: point, with: event) }
        return drawing.strokes.contains { $0.renderBounds.insetBy(dx: -16, dy: -16).contains(point) }
    }
}
