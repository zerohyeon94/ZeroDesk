import PencilKit
import SwiftUI

/// 절 하나 위에 얹는 투명한 필기 층.
/// 필기 모드가 아니면 그림만 보여 주고 손을 대지 않는다 (링크 누르기·스크롤은 아래 본문이 받는다).
/// 필기 모드에서는 Pencil로만 그리고, 손가락으로는 그대로 스크롤한다.
struct InkCanvas: UIViewRepresentable {
    /// 저장된 필기 (`PKDrawing.dataRepresentation()`). 밖에서 바뀔 때만 다시 그린다.
    let data: Data?
    let editing: Bool
    /// 본문이 바뀌어 위치가 어긋났을 수 있는 필기: 흐리게, 고칠 수 없게.
    let stale: Bool
    /// 지금 읽는 절. 필기 모드를 켜면 이 절이 도구 막대를 받는다.
    let focused: Bool
    let toolPicker: PKToolPicker
    let onChange: (PKDrawing, Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
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

    func updateUIView(_ v: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        if data != context.coordinator.lastData, !context.coordinator.drawingInProgress {
            context.coordinator.apply(data, to: v)
        }
        let canEdit = editing && !stale
        v.isUserInteractionEnabled = canEdit
        v.alpha = stale ? 0.35 : 1
        if canEdit {
            toolPicker.addObserver(v)
            toolPicker.setVisible(true, forFirstResponder: v)
            if focused, !v.isFirstResponder { DispatchQueue.main.async { v.becomeFirstResponder() } }
        } else {
            toolPicker.removeObserver(v)
            if v.isFirstResponder { v.resignFirstResponder() }
        }
    }

    static func dismantleUIView(_ v: PKCanvasView, coordinator: Coordinator) {
        if v.isFirstResponder { v.resignFirstResponder() }
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
            // 그리기 시작한 절이 도구 막대를 받는다.
            if !v.isFirstResponder { v.becomeFirstResponder() }
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
