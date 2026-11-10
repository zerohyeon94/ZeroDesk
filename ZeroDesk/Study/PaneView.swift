import SwiftUI
import ZeroDeskCore

/// 칸 하나에 쌓이는 화면: 파일 경로와 이동할 제목.
struct Route: Hashable {
    var path: String
    var heading: String?
}

/// 학습 파일 칸 하나: 파일 스택, 파일 바꾸기(⇄), 링크 처리 (스펙 4.2, 6).
/// `root`가 비어 있으면 파일 목록을 보여 준다.
struct PaneView: View {
    @Binding var root: String
    @Binding var stack: [Route]
    /// 링크를 다른 칸에서 열 때. `nil`이면 이 칸에 쌓는다.
    var openElsewhere: ((Route) -> Void)?
    @Environment(VaultStore.self) private var store
    @State private var switching = false
    @State private var missing = false

    var body: some View {
        NavigationStack(path: $stack) {
            page(Route(path: root))
                .navigationDestination(for: Route.self) { page($0) }
        }
        .environment(\.openURL, OpenURLAction(handler: handle))
        .sheet(isPresented: $switching) {
            NavigationStack {
                FileBrowserView { path in
                    root = path
                    stack = []
                    switching = false
                }
                .navigationTitle("파일 바꾸기")
                .toolbar { Button("닫기") { switching = false } }
            }
        }
        .alert("파일을 찾지 못함", isPresented: $missing) {}
    }

    @ViewBuilder private func page(_ r: Route) -> some View {
        if r.path.isEmpty {
            FileBrowserView { stack.append(Route(path: $0)) }.navigationTitle("학습 파일")
        } else {
            FileView(path: r.path, heading: r.heading)
                .id(r)
                .navigationTitle(((r.path as NSString).lastPathComponent as NSString).deletingPathExtension)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { switching = true } label: { Image(systemName: "arrow.left.arrow.right") }
                            .accessibilityLabel("파일 바꾸기")
                    }
                }
        }
    }

    private func handle(_ url: URL) -> OpenURLAction.Result {
        if let link = AppLink.parse(url), link.kind == "open" {
            let current = stack.last?.path ?? root
            let resolved = link.target.isEmpty ? current : store.index.resolve(link.target)
            guard let path = resolved else {
                missing = true
                return .handled
            }
            let r = Route(path: path, heading: link.heading)
            if let openElsewhere { openElsewhere(r) } else { stack.append(r) }
            return .handled
        }
        if url.scheme == "http" || url.scheme == "https" { return .systemAction }
        return .discarded
    }
}
