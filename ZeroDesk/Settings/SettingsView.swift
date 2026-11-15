import SwiftUI

/// 설정: 볼트를 읽는 곳(iCloud 폴더 또는 GitHub), 마지막 갱신 시각, 지금 새로고침 (스펙 4.3).
struct SettingsView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        NavigationStack {
            Form {
                Section("볼트") {
                    LabeledContent("읽는 곳", value: store.readsGitHub ? "GitHub \(store.githubRepo)" : "iCloud 폴더")
                    if let problem = store.syncProblem {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    FolderPickButton(title: store.readsGitHub ? "iCloud 폴더에서 읽기" : "볼트 폴더 다시 고르기")
                }
                GitHubSection()
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

/// GitHub 저장소와 토큰 입력. 설정과 첫 화면에서 같이 쓴다.
struct GitHubSection: View {
    var onDone: () -> Void = {}
    @Environment(VaultStore.self) private var store
    @State private var repo = ""
    @State private var token = ""

    var body: some View {
        Section {
            TextField("owner/name", text: $repo)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(store.readsGitHub ? "새 토큰 (바꿀 때만)" : "토큰", text: $token)
            Button(store.readsGitHub ? "토큰 바꾸기" : "GitHub에서 읽기") {
                let repo = repo.trimmingCharacters(in: .whitespaces)
                let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                self.token = ""
                Task {
                    await store.useGitHub(repo: repo, token: token)
                    onDone()
                }
            }
            .disabled(token.isEmpty || !repo.contains("/"))
        } header: {
            Text("GitHub")
        } footer: {
            Text("이 저장소만 Contents 읽기로 허용한 fine-grained 토큰을 넣는다. 토큰은 이 기기의 Keychain에만 저장한다.")
        }
        .onAppear { if repo.isEmpty { repo = store.githubRepo } }
    }
}
