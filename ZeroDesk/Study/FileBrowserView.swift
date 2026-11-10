import SwiftUI

/// 파일 목록: 자주 쓰는 곳 셋(최근 수정 5개)과 전체 폴더 트리 (스펙 4.2).
struct FileBrowserView: View {
    var onPick: (String) -> Void
    @Environment(VaultStore.self) private var store

    private struct Node: Identifiable {
        var id: String
        var name: String
        var children: [Node]?
    }

    var body: some View {
        let md = store.files.filter { $0.path.hasSuffix(".md") }
        List {
            ForEach(["Learning/개념", "Daily", "Schedule"], id: \.self) { folder in
                let recent = md.filter { $0.path.hasPrefix(folder + "/") }.sorted { $0.modified > $1.modified }.prefix(5)
                if !recent.isEmpty {
                    Section(folder) {
                        ForEach(recent, id: \.path) { f in row(f.path) }
                    }
                }
            }
            Section("전체 폴더") {
                OutlineGroup(tree(md.map(\.path)), children: \.children) { node in
                    if node.children == nil { row(node.id) } else { Label(node.name, systemImage: "folder") }
                }
            }
        }
        .refreshable { await store.refresh() }
    }

    private func row(_ path: String) -> some View {
        Button { onPick(path) } label: {
            Label(((path as NSString).lastPathComponent as NSString).deletingPathExtension, systemImage: "doc.text")
        }
    }

    /// 경로 목록 → 폴더 트리. 폴더 먼저, 이름순.
    private func tree(_ paths: [String]) -> [Node] {
        func build(_ prefix: String, _ rest: [[Substring]]) -> [Node] {
            let groups = Dictionary(grouping: rest.filter { !$0.isEmpty }) { String($0[0]) }
            return groups.map { name, items -> Node in
                let id = prefix.isEmpty ? name : prefix + "/" + name
                let deeper = items.filter { $0.count > 1 }.map { Array($0.dropFirst()) }
                return deeper.isEmpty ? Node(id: id, name: name, children: nil) : Node(id: id, name: name, children: build(id, deeper))
            }
            .sorted { ($0.children == nil ? 1 : 0, $0.name) < ($1.children == nil ? 1 : 0, $1.name) }
        }
        return build("", paths.map { $0.split(separator: "/") })
    }
}
