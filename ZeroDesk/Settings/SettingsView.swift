import SwiftUI

/// 설정: 볼트 폴더 다시 고르기, 마지막 갱신 시각, 지금 새로고침 (스펙 4.3).
struct SettingsView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        NavigationStack {
            Form {
                Section("볼트") { FolderPickButton(title: "볼트 폴더 다시 고르기") }
                Section("갱신") {
                    LabeledContent("마지막 갱신", value: store.lastRefresh.map(Self.time.string(from:)) ?? "—")
                    Button("지금 새로고침") { Task { await store.refresh() } }
                }
            }
            .navigationTitle("설정")
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
