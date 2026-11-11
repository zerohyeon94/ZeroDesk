import Foundation
import Observation
import PencilKit
import ZeroDeskCore

/// 노트 하나의 필기를 읽고, 바뀌면 잠시 뒤 볼트 숨김 폴더에 저장한다.
@Observable @MainActor
final class NoteInk {
    enum State: Equatable { case loading, ready, failed }

    let notePath: String
    private(set) var state: State = .loading
    private(set) var file = InkFile()
    /// 저장 실패를 화면에 알린다.
    private(set) var saveFailed = false

    @ObservationIgnored private let store: VaultStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false

    init(notePath: String, store: VaultStore) {
        self.notePath = notePath
        self.store = store
    }

    private var inkPath: String { InkFile.path(for: notePath) }

    func load() async {
        do {
            if let data = try await store.dataIfExists(of: inkPath) { file = try InkFile.decode(data) }
            state = .ready
        } catch {
            // 있는데 못 읽은 필기는 덮어쓰지 않도록 필기를 막는다.
            state = .failed
        }
    }

    func data(_ key: String) -> Data? { file.sections[key]?.drawing }

    func set(_ drawing: PKDrawing, data: Data, key: String, hash: String, layout: String) {
        guard state == .ready else { return }
        if drawing.strokes.isEmpty {
            guard file.sections.removeValue(forKey: key) != nil else { return }
        } else {
            file.sections[key] = .init(hash: hash, layout: layout, drawing: data)
        }
        scheduleSave()
    }

    func highlights(in section: String) -> [Highlight] { file.highlights.filter { $0.section == section } }

    func add(_ h: Highlight) {
        guard state == .ready else { return }
        file.highlights.append(h)
        scheduleSave()
    }

    func highlight(_ id: UUID) -> Highlight? { file.highlights.first { $0.id == id } }

    /// 메모를 달거나 고치거나(`memo`), 없앤다(`nil`).
    func setMemo(_ memo: HighlightMemo?, for id: UUID) {
        guard state == .ready, let i = file.highlights.firstIndex(where: { $0.id == id }) else { return }
        file.highlights[i].memo = memo
        scheduleSave()
    }

    func remove(highlight id: UUID) {
        guard state == .ready else { return }
        file.highlights.removeAll { $0.id == id }
        scheduleSave()
    }

    /// 본문이 바뀐 절의 필기를 지금 본문에 맞는 것으로 받아들인다.
    func accept(key: String, hash: String, layout: String) {
        guard state == .ready, var s = file.sections[key] else { return }
        s.hash = hash
        s.layout = layout
        file.sections[key] = s
        scheduleSave()
    }

    func clear(key: String) {
        guard state == .ready, file.sections.removeValue(forKey: key) != nil else { return }
        scheduleSave()
    }

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// 화면을 떠날 때 기다리지 않고 바로 저장한다.
    func flush() async {
        saveTask?.cancel()
        await save()
    }

    private func save() async {
        guard dirty, state == .ready else { return }
        dirty = false
        do {
            try await store.write(try file.encoded(), to: inkPath)
            saveFailed = false
        } catch {
            dirty = true
            saveFailed = true
        }
    }
}
