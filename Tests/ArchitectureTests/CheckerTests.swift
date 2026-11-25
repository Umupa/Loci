import Testing

/// The checks above are only as good as the reader underneath them.
struct CheckerTests {
  @Test func tellsCommentsFromCodeAndStrings() {
    let lines = SourceFile.parse(
      """
      let site = "https://loci.app" // trailing
      /// Promises something.
      let slashes = "// not a comment"
      /* block
      still */ let after = 1
      let text = \"\"\"
        // inside a string
        \"\"\"
      """)

    #expect(lines.map(\.remark) == [.plain, .documentation, nil, .plain, .plain, nil, nil, nil])
    #expect(lines[0].code.contains("let site"))
    #expect(!lines[2].code.contains("not a comment"))
    #expect(lines[4].code.contains("let after"))
  }

  @Test func readsImports() {
    let file = SourceFile(
      path: "Sources/LociUI/Example.swift", module: "LociUI",
      text: """
        import SwiftUI
        @testable import LociModel
        import struct Foundation.URL
        let note = "import Nothing"
        """)

    #expect(file.imports.map(\.name) == ["SwiftUI", "LociModel", "Foundation"])
  }

  @Test func flagsAnImportAcrossTheBoundary() {
    let file = SourceFile(
      path: "Sources/LociUI/Example.swift", module: "LociUI", text: "import LociStore\nimport GRDB\nimport SwiftUI")

    let found = BoundaryTests.importViolations(in: file).map(\.found)

    #expect(found == ["LociUI imports LociStore", "LociUI imports GRDB"])
  }

  @Test func flagsForbiddenAndRestrictedConstructs() {
    let file = SourceFile(
      path: "Sources/LociUI/Example.swift", module: "LociUI",
      text: """
        let data = try! load()
        let message = "print(x) and try! are fine inside a string"
        let files = FileManager.default
        DispatchQueue.main.async {}
        """)

    #expect(BoundaryTests.violations(of: Architecture.forbidden, in: file).map(\.line) == [1, 4])
    #expect(BoundaryTests.violations(of: Architecture.restricted, in: file).map(\.line) == [3])
  }

  @Test func flagsACapsuleStrokedWithItsDefaultCorners() {
    let file = SourceFile(
      path: "Sources/LociUI/Example.swift", module: "LociUI",
      text: """
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
        .overlay(Capsule(style: .circular).strokeBorder(Palette.line, lineWidth: 1))
        .background(Capsule().fill(Palette.surface))
        """)

    #expect(BoundaryTests.violations(of: Architecture.forbidden, in: file).map(\.line) == [1])
  }

  @Test func flagsAWriteToTheCalendarOutsideApprovals() {
    let text = """
      let event = EKEvent(eventStore: store)
      try store.save(event, span: .thisEvent, commit: true)
      let events = store.events(matching: predicate)
      """
    let data = SourceFile(path: "Sources/LociConnect/EventKitData.swift", module: "LociConnect", text: text)
    let writes = SourceFile(path: "Sources/LociConnect/PersonalWrites.swift", module: "LociConnect", text: text)

    #expect(BoundaryTests.violations(of: Architecture.forbidden, in: data).map(\.line) == [1, 2])
    #expect(BoundaryTests.violations(of: Architecture.forbidden, in: writes).isEmpty)
  }

  @Test func flagsANotificationASoundOrADockBadge() {
    let file = SourceFile(
      path: "Sources/LociUI/Example.swift", module: "LociUI",
      text: """
        UNUserNotificationCenter.current().add(request)
        NSSound(named: "Glass")?.play()
        NSApp.dockTile.badgeLabel = "3"
        NSApp.requestUserAttention(.informationalRequest)
        let deck = NextUpDeck(cards: cards)
        """)

    #expect(BoundaryTests.violations(of: Architecture.forbidden, in: file).map(\.line) == [1, 2, 3, 4])
  }

  @Test func flagsASparklesSymbolInAnyCase() {
    let file = SourceFile(
      path: "Sources/LociUI/Example.swift", module: "LociUI",
      text: """
        static let magic = "sparkles"
        Image(systemName: "wand.and.Sparkles")
        let fine = "list.star"
        """)

    #expect(CodeRuleTests.symbolViolations(in: file).map(\.line) == [1, 2])
  }

  @Test func ownersMayUseWhatTheyOwn() {
    let file = SourceFile(
      path: "Sources/LociStore/Example.swift", module: "LociStore", text: "let files = FileManager.default")

    #expect(BoundaryTests.violations(of: Architecture.restricted, in: file).isEmpty)
  }

  @Test func onlyTheNamedBridgeFileMayUseGCD() {
    let bridge = SourceFile(
      path: "Sources/LociStore/FileEvents.swift", module: "LociStore", text: "let queue = DispatchQueue(label: \"x\")")
    let elsewhere = SourceFile(
      path: "Sources/LociStore/Other.swift", module: "LociStore", text: "let queue = DispatchQueue(label: \"x\")")

    #expect(BoundaryTests.violations(of: Architecture.forbidden, in: bridge).isEmpty)
    #expect(BoundaryTests.violations(of: Architecture.forbidden, in: elsewhere).map(\.line) == [1])
  }

  @Test func approvedPackagesMayBeImportedOnlyWhereListed() {
    let store = SourceFile(path: "Sources/LociStore/Example.swift", module: "LociStore", text: "import GRDB")
    let model = SourceFile(path: "Sources/LociModel/Example.swift", module: "LociModel", text: "import GRDB")

    #expect(BoundaryTests.importViolations(in: store).isEmpty)
    #expect(BoundaryTests.importViolations(in: model).map(\.found) == ["LociModel imports GRDB"])
  }

  @Test func flagsPlainCommentsButNotDocumentation() {
    let file = SourceFile(
      path: "Sources/LociModel/Example.swift", module: "LociModel",
      text: "/// Kept.\nlet a = 1\n// removed\nlet b = 2 // also removed")

    #expect(CodeRuleTests.commentViolations(in: file).map(\.line) == [3, 4])
  }
}
