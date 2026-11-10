import Foundation

/// 테스트 자료(볼트 사본)를 읽는다.
func fixture(_ relPath: String) throws -> String {
    let url = Bundle.module.url(forResource: "Fixtures/vault", withExtension: nil)!.appending(path: relPath)
    return try String(contentsOf: url, encoding: .utf8)
}
