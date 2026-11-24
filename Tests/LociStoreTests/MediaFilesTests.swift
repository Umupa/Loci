import Foundation
import LociModel
import Testing

@testable import LociStore

struct MediaFilesTests {
  static func video(_ title: String = "youtube.com watch") throws -> Item {
    try Item(id: Fixture.id(3), kind: .video(duration: nil), title: title, source: URL(string: "https://youtu.be/x"))
  }

  @Test func aPendingItemHasOnlyItsItemFileUntilItsContentArrives() throws {
    try withStore { store in
      let item = try Self.video()
      try store.addPending(item)

      #expect(try store.item(item.id) == item)
      #expect(try store.transcript(of: item.id) == nil)
      #expect(try store.outline(of: item.id) == nil)
      #expect(try store.mediaFile(of: item.id) == nil)
      #expect(try store.fetchedContent(of: item.id) == nil)
      #expect(try store.translations(of: item.id).isEmpty)
    }
  }

  @Test func onceTheTitleIsKnownTheFolderIsNamedAfterIt() throws {
    try withStore { store in
      let pending = try Self.video()
      try store.addPending(pending)
      let titled = try Item(id: pending.id, kind: .video(duration: .seconds(19)), title: "Me at the zoo")

      try store.retitle(titled, from: pending.title)

      #expect(try store.itemFolder(pending.id).lastPathComponent == "me-at-the-zoo-\(pending.id)")
      #expect(try store.item(pending.id) == titled)
    }
  }

  @Test func aFolderRenamedByHandKeepsItsName() throws {
    try withStore { store in
      let pending = try Self.video()
      try store.addPending(pending)
      let folder = try store.itemFolder(pending.id)
      let mine = folder.deletingLastPathComponent().appending(path: "my-zoo-\(pending.id)")
      try FileManager.default.moveItem(at: folder, to: mine)

      try store.retitle(
        try Item(id: pending.id, kind: .video(duration: nil), title: "Me at the zoo"), from: pending.title)

      #expect(try store.itemFolder(pending.id).lastPathComponent == "my-zoo-\(pending.id)")
    }
  }

  @Test func transcriptsTranslationsOutlinesAndKeyPointsReadBackAsWritten() throws {
    try withStore { store in
      let item = try Self.video()
      try store.addPending(item)
      let transcript = try Transcript(
        language: "en", origin: .recognized(.base),
        segments: [try .init(start: .zero, end: .seconds(2), text: "All right, so here we are")])
      let translation = try Translation(language: "zh-Hans", lines: ["好，我们到了"])
      let outline = try Outline(chapters: [try .init(start: .zero, title: "Intro")])
      let keyPoints = try KeyPoints(
        points: [try KeyPoint(place: .time(try TimeSpan(start: .zero, end: .seconds(2))), title: "开场", reason: "第一句")],
        choice: KeyPointChoice(
          model: ModelChoice(provider: ModelProviderID(.deepSeek), model: "deepseek-chat"), count: .few))

      try store.save(transcript, of: item.id)
      try store.save(translation, of: item.id)
      try store.save(outline, of: item.id)
      try store.save(keyPoints, of: item.id)

      #expect(try store.transcript(of: item.id) == transcript)
      #expect(try store.translations(of: item.id) == [translation])
      #expect(try store.outline(of: item.id) == outline)
      #expect(try store.keyPoints(of: item.id) == keyPoints)
      #expect(
        FileManager.default.fileExists(
          atPath: try store.itemFolder(item.id).appending(path: "translations/zh-Hans.json").path))
    }
  }

  @Test func aFinishedDownloadMovesInAsTheItemsMedia() throws {
    try withStore { store in
      let item = try Self.video()
      try store.addPending(item)
      let work = try store.workFolder(of: item.id)
      let download = work.appending(path: "media.mp4")
      try Data("movie".utf8).write(to: download)

      let media = try store.adoptMedia(download, of: item.id)
      try store.clearWork(of: item.id)

      #expect(media.lastPathComponent == "media.mp4")
      #expect(try store.mediaFile(of: item.id) == media)
      #expect(!FileManager.default.fileExists(atPath: work.path))
    }
  }

  @Test func anImportedFileIsCopiedOrLinked() throws {
    try withStore { store in
      let outside = store.root.appending(path: "outside/talk.MOV")
      try FileManager.default.createDirectory(
        at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("talk".utf8).write(to: outside)
      let copied = try Item(id: Fixture.id(4), kind: .video(duration: nil), title: "talk")
      let linked = try Item(id: Fixture.id(5), kind: .video(duration: nil), title: "talk linked")
      try store.addPending(copied)
      try store.addPending(linked)

      let copy = try store.importMedia(outside, as: .copy, of: copied.id)
      let link = try store.importMedia(outside, as: .link, of: linked.id)

      #expect(copy.lastPathComponent == "media.mov")
      #expect(try Data(contentsOf: copy) == Data("talk".utf8))
      #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == outside.path)
      #expect(throws: StoreError.self) {
        try store.importMedia(store.root.appending(path: "missing.mp4"), as: .copy, of: copied.id)
      }
    }
  }

  @Test func theCoverIsKeptWithItsOwnExtension() throws {
    try withStore { store in
      let item = try Self.video()
      try store.addPending(item)

      try store.saveCover(Data("png".utf8), extension: "PNG", of: item.id)
      try store.saveCover(Data("jpg".utf8), extension: "jpg", of: item.id)

      #expect(try store.coverFile(of: item.id)?.lastPathComponent == "cover.jpg")
      #expect(try store.cover(of: item.id) == Data("jpg".utf8))
    }
  }

  @Test func anArticleKeepsItsPicturesBesideItsText() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.addPending(item)

      try store.saveArticle("# Borg\n\n![](images/a.png)\n", images: ["a.png": Data("png".utf8)], of: item.id)

      #expect(try store.content(of: item.id) == "# Borg\n\n![](images/a.png)\n")
      #expect(try store.image(named: "a.png", of: item.id) == Data("png".utf8))
      for name in ["../item.json", "/etc/hosts", "..", ".hidden", ""] {
        #expect(throws: StoreError.self) { try store.image(named: name, of: item.id) }
      }
    }
  }

  @Test func anArticlesTranslationIsKeptPerLanguage() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.addPending(item)
      try store.saveArticle("# Borg\n", images: [:], of: item.id)
      #expect(try store.articleTranslation(of: item.id, into: "zh-Hans") == nil)

      let translation = try ArticleTranslation(
        language: "zh-Hans", passages: [.init(source: "# Borg", text: "# Borg 集群管理")])
      try store.save(translation, of: item.id)

      #expect(try store.articleTranslation(of: item.id, into: "zh-Hans") == translation)
      #expect(try store.articleTranslation(of: item.id, into: "ja") == nil)
      #expect(throws: StoreError.self) { try store.articleTranslation(of: item.id, into: "../item") }
    }
  }

  @Test func aPaperKeepsItsPDF() throws {
    try withStore { store in
      let item = try Item(id: Fixture.id(6), kind: .paper, title: "Borg")
      try store.addPending(item)

      try store.savePDF(Data("%PDF".utf8), of: item.id)

      #expect(try store.pdf(of: item.id) == Data("%PDF".utf8))
    }
  }

  @Test func filesTheReaderSeesReportTheirItemButWorkInProgressDoesNot() {
    let folder = ChangeMapTests.itemFolder
    for file in [
      "transcript.json", "outline.json", "translations/zh-Hans.json", "cover.jpg", "media.mp4", "content.pdf",
      "images/a.png",
    ] {
      #expect(ChangeMapTests.changes(["\(folder)/\(file)"]) == [.item(ChangeMapTests.item)], "\(file)")
    }
    #expect(ChangeMapTests.changes(["\(folder)/.work/media.f137.mp4.part"]).isEmpty)
  }
}
