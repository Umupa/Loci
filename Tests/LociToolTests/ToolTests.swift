import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociTool

/// A line that answers from a script and keeps what was sent.
final class ScriptedLine: LocalLine {
  private let sent = Mutex<[LocalCall.Request]>([])
  private let answers: @Sendable (LocalCall.Request) -> [Result<Data, Failure>]

  init(_ answers: @escaping @Sendable (LocalCall.Request) -> [Result<Data, Failure>]) {
    self.answers = answers
  }

  var requests: [LocalCall.Request] { sent.withLock { $0 } }

  func send(_ request: LocalCall.Request, until accepts: @escaping @Sendable (Data) -> Bool) async throws(Failure)
    -> Data
  {
    sent.withLock { $0.append(request) }
    for answer in answers(request) {
      let data = try answer.get()
      if accepts(data) { return data }
    }
    throw .socket(.closed)
  }
}

struct ToolTests {
  private static let id = EntityID("019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f") ?? EntityID()
  private static let item = (try? Item(id: id, kind: .article, title: "Borg", authors: ["Loci"]))

  private static func json(_ value: some Encodable) -> Data {
    (try? Failure.encoding(value)) ?? Data()
  }

  private static func name(_ request: LocalCall.Request) -> String {
    switch request {
    case .command(let name, _), .follow(let name, _): name
    case .upload: "upload"
    case .itemFolder: "itemFolder"
    case .course: "course"
    }
  }

  private func tool(_ line: ScriptedLine, read: @escaping @Sendable (URL) throws -> String = { _ in "" }) -> Tool {
    Tool(line: line, folder: URL(filePath: "/loci/agent/"), readText: read)
  }

  @Test func searchPrintsEachHitWithItsTitle() async throws {
    let item = try #require(Self.item)
    let hit = SearchHit(target: .item(Self.id), field: .body, snippet: "Borg admits jobs", locator: nil)
    let line = ScriptedLine { request in
      Self.name(request) == Search.name ? [.success(Self.json([hit]))] : [.success(Self.json([item]))]
    }

    let outcome = await tool(line).run(.search("admits"), json: false)

    #expect(outcome == .worked("\(Self.id)  Borg\n    Borg admits jobs"))
    #expect(line.requests.map(Self.name) == [Search.name, ListItems.name])
  }

  @Test func jsonPrintsTheAppsReplyAsItIs() async throws {
    let reply = Data(#"[{"field":"title"}]"#.utf8)
    let line = ScriptedLine { _ in [.success(reply)] }

    let outcome = await tool(line).run(.search("borg"), json: true)

    #expect(outcome == .worked(#"[{"field":"title"}]"#))
    #expect(line.requests.count == 1)
  }

  @Test func readPrintsTheFullSourceExactlyAsTheAppReturnedIt() async throws {
    let url = try #require(URL(string: "https://example.com/long"))
    let text = String(repeating: "正文\n", count: 100_000) + "Last line"
    let reply = Self.json(text)
    let line = ScriptedLine { _ in [.success(reply)] }

    let plain = await tool(line).run(.read(url), json: false)
    let json = await tool(line).run(.read(url), json: true)

    #expect(plain.status == 0)
    #expect(plain.output == text)
    #expect(json == .worked(Tool.text(reply)))
    #expect(line.requests.first == .command(name: ReadSource.name, body: Self.json(ReadSource(url: url))))
  }

  @Test func repoPrintsTheAbsolutePathAndCommitSeparatedByATab() async throws {
    let url = try #require(URL(string: "https://example.com/repository"))
    let commit = try #require(CommitID(String(repeating: "a", count: 40)))
    let checkout = SourceCheckout(
      path: "/Users/reader/Library/Caches/Loci-Beta/sources/repo with spaces", commit: commit)
    let line = ScriptedLine { _ in [.success(Self.json(checkout))] }

    let result = await tool(line).run(.repo(url, commit: commit), json: false)

    #expect(result == .worked("\(checkout.path)\t\(commit)"))
    #expect(
      line.requests == [
        .command(name: FetchSourceRepository.name, body: Self.json(FetchSourceRepository(url: url, commit: commit)))
      ])
  }

  @Test func readSaysWhyTheSourceCannotBeRead() async throws {
    let url = try #require(URL(string: "https://example.com/missing"))
    let line = ScriptedLine { _ in [.failure(.host(.invalidRequest("The source could not be found (HTTP 404).")))] }

    let result = await tool(line).run(.read(url), json: false)

    #expect(result.status == 1)
    #expect(result.text.contains("HTTP 404"))
  }

  @Test func saveIsALinkAddedAndPrintsTheIdAtOnce() async throws {
    let item = try #require(Self.item)
    let url = try #require(URL(string: "https://example.com/borg"))
    let line = ScriptedLine { _ in [.success(Self.json(item))] }

    let outcome = await tool(line).run(.save(url), json: false)

    #expect(line.requests == [.command(name: AddLink.name, body: Self.json(AddLink(url: url)))])
    #expect(outcome.status == 0)
    #expect(outcome.text.hasPrefix("\(Self.id)  Borg"))
  }

  @Test func anArticleIsImportedWithLociAsItsAuthor() async throws {
    let item = try #require(Self.item)
    let line = ScriptedLine { _ in [.success(Self.json(item))] }
    let folder = FileManager.default.temporaryDirectory.appending(path: "loci-tool-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appending(path: "workspace"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("# Borg\n".utf8).write(to: folder.appending(path: "workspace/borg.md"))
    let tool = Tool(line: line, folder: folder) { try String(contentsOf: $0, encoding: .utf8) }

    _ = await tool.run(.importFile(path: "workspace/borg.md", title: "Borg"), json: false)

    let expected = AddTextItem(fileName: "borg.md", text: "# Borg\n", title: "Borg", authors: ["Loci"])
    #expect(line.requests == [.command(name: AddTextItem.name, body: Self.json(expected))])
  }

  @Test func aFileThatIsNotThereIsNotSent() async {
    let line = ScriptedLine { _ in [] }

    let outcome = await tool(line).run(.importFile(path: "/nowhere/talk.mp4", title: nil), json: false)

    #expect(outcome == .failed("There is no file at /nowhere/talk.mp4."))
    #expect(line.requests.isEmpty)
  }

  @Test func aMediaFileIsUploadedThenImported() async throws {
    let item = try #require(Self.item)
    let upload = Upload(id: Self.id)
    let line = ScriptedLine { request in
      Self.name(request) == "upload" ? [.success(Self.json(upload))] : [.success(Self.json(item))]
    }

    let file = FileManager.default.temporaryDirectory.appending(path: "talk-\(UUID().uuidString).mp4")
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    _ = await tool(line).run(.importFile(path: file.path, title: nil), json: false)

    #expect(
      line.requests == [
        .upload(path: file.path),
        .command(name: ImportMediaFile.name, body: Self.json(ImportMediaFile(upload: upload, mode: .copy))),
      ])
  }

  @Test func waitReturnsWhenTheJobIsDone() async {
    let running = Feed<Job?>.value(Job(item: Self.id, stage: .extract, state: .running(progress: nil)))
    let line = ScriptedLine { _ in [.success(Self.json(running)), .success(Self.json(Feed<Job?>.value(nil)))] }

    let outcome = await tool(line).run(.wait(Self.id), json: false)

    #expect(outcome == .worked("\(Self.id) is ready."))
    #expect(line.requests == [.follow(name: ItemJob.name, body: Self.json(ItemJob(item: Self.id)))])
  }

  @Test func waitSaysWhyAJobFailed() async {
    let failed = Job(item: Self.id, stage: .extract, state: .failed(.init(reason: "403", remedy: .openSource)))
    let line = ScriptedLine { _ in [.success(Self.json(Feed<Job?>.value(failed)))] }

    let outcome = await tool(line).run(.wait(Self.id), json: false)

    #expect(outcome.status == 1)
    #expect(outcome.text.contains("403"))
  }

  @Test func showGivesTheItemItsJobAndItsFolder() async throws {
    let item = try #require(Self.item)
    let line = ScriptedLine { request in
      switch Self.name(request) {
      case ListItems.name: [.success(Self.json([item]))]
      case ItemJob.name: [.success(Self.json(Feed<Job?>.value(nil)))]
      default: [.success(Self.json("../library/borg-\(Self.id)/"))]
      }
    }

    let outcome = await tool(line).run(.show(Self.id), json: false)

    #expect(
      outcome
        == .worked(
          "Borg\nid: \(Self.id)\nkind: article\nauthors: Loci\njob: done\nfolder: ../library/borg-\(Self.id)/"))
  }

  @Test func anErrorFromTheAppSaysWhatToDo() async {
    let line = ScriptedLine { _ in [.failure(.host(.notFound("x")))] }

    let outcome = await tool(line).run(.show(Self.id), json: false)

    #expect(outcome.status == 1)
    #expect(outcome.text.contains("loci search"))
  }
}
