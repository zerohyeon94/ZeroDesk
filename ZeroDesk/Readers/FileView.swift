import SwiftUI
import ZeroDeskCore

/// 파일 하나를 읽어 경로에 맞는 방식(대기열·Daily·길게 읽기)으로 보여 준다 (스펙 5).
struct FileView: View {
    let path: String
    var heading: String?
    @Environment(VaultStore.self) private var store
    @State private var state: LoadState = .loading

    enum LoadState { case loading, loaded(String), failed(String) }

    init(path: String, heading: String? = nil) {
        self.path = path
        self.heading = heading
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("iCloud에서 받는 중").frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label(message, systemImage: "icloud.slash")
                } actions: {
                    Button("다시 시도") { Task { await load() } }
                }
            case let .loaded(text):
                switch NoteLayout.forPath(path) {
                case .queue: QueueProgressView(text: text, path: path)
                case .daily: DailyCardsView(doc: NoteDocument.parse(text))
                case .longRead: NoteReaderView(doc: NoteDocument.parse(text), path: path, heading: heading)
                }
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await store.text(of: path))
        } catch VaultError.notDownloaded {
            state = .failed("iCloud에서 아직 받지 못함")
        } catch {
            state = .failed("파일을 읽지 못함")
        }
    }
}
