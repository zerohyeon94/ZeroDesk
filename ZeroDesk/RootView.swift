import SwiftUI
import UniformTypeIdentifiers

/// 첫 실행이면 폴더 고르기, 아니면 탭 셋: 홈 · 학습 파일 · 설정 (스펙 4, 8).
struct RootView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// 시뮬레이터 확인용: -startTab <번호> 로 처음 열 탭을 고른다 (기본 홈).
    @State private var tab = UserDefaults.standard.integer(forKey: "startTab")
    @State private var request: Route?
    @State private var started = false

    var body: some View {
        Group {
            switch store.phase {
            case .needsFolder:
                FolderPickView(message: "iCloud Drive의 Obsidian 폴더에서 볼트(zerohyeon-labs)를 골라 주세요.")
            case let .failed(message):
                FolderPickView(message: message, retry: true)
            case .loading where store.home == nil:
                ProgressView("iCloud에서 받는 중")
            default:
                TabView(selection: $tab) {
                    Tab("홈", systemImage: "house", value: 0) {
                        HomeView { path in
                            request = Route(path: path)
                            tab = 1
                        }
                    }
                    Tab("학습 파일", systemImage: "book", value: 1) { StudyView(request: $request) }
                    Tab("설정", systemImage: "gear", value: 2) { SettingsView() }
                }
            }
        }
        .task {
            #if DEBUG
            tab = UserDefaults.standard.integer(forKey: "startTab")  // 시뮬레이터 확인용: -startTab 1
            #endif
            await store.start()
            started = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, started { Task { await store.refresh() } }
        }
    }
}

/// 볼트 폴더 고르기 버튼. 첫 화면과 설정에서 같이 쓴다.
struct FolderPickButton: View {
    var title = "볼트 폴더 고르기"
    @Environment(VaultStore.self) private var store
    @State private var importing = false

    var body: some View {
        Button(title) { importing = true }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
                if case let .success(url) = result { Task { await store.pick(folder: url) } }
            }
    }
}

private struct FolderPickView: View {
    let message: String
    var retry = false
    @Environment(VaultStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("ZeroDesk", systemImage: "folder")
        } description: {
            Text(message)
        } actions: {
            FolderPickButton().buttonStyle(.borderedProminent)
            if retry { Button("다시 시도") { Task { await store.refresh() } } }
        }
    }
}
