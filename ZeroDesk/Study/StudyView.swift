import SwiftUI
import ZeroDeskCore

/// 학습 파일 탭. iPad는 2단(왼쪽 40%), iPhone은 한 칸 (스펙 4.2).
struct StudyView: View {
    @Binding var request: Route?
    @Environment(VaultStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("pane.left") private var leftPath = HomeSnapshot.queuePath
    @AppStorage("pane.right") private var rightPath = ""
    @State private var leftStack: [Route] = []
    @State private var rightStack: [Route] = []
    @State private var compactStack: [Route] = []
    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    PaneView(root: $leftPath, stack: $leftStack) { rightStack.append($0) }
                        .frame(width: width * 0.4)
                    Divider()
                    PaneView(root: $rightPath, stack: $rightStack)
                }
            } else {
                PaneView(root: .constant(""), stack: $compactStack)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear {
            // 오른쪽 칸 기본값 = 오늘 개념
            if rightPath.isEmpty, let p = store.home?.month?.currentLink.flatMap(store.index.resolve) { rightPath = p }
            take()
        }
        .onChange(of: request) { _, _ in take() }
    }

    /// 홈에서 연 파일은 오른쪽 칸(iPhone은 한 칸)을 그 파일로 바꾼다.
    private func take() {
        guard let r = request else { return }
        request = nil
        if sizeClass == .regular {
            rightPath = r.path
            rightStack = []
        } else {
            compactStack = [r]
        }
    }
}
