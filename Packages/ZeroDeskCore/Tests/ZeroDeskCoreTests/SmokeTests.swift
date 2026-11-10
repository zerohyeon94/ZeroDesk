import Testing
import ZeroDeskCore

@Test func markdownParses() { #expect(Document(parsing: "# a").childCount == 1) }
