import Foundation
import LociModel

/// Carries out one request over a line to the app, and says what came of it.
struct Tool: Sendable {
  let line: any LocalLine
  /// Where a relative file path starts.
  let folder: URL
  let readText: @Sendable (URL) throws -> String
  /// Everything on standard input, read when a command takes it.
  var readInput: @Sendable () -> Data = { FileHandle.standardInput.readDataToEndOfFile() }
  /// The id of an item Loci adds to a panel.
  var newID: @Sendable () -> EntityID = { EntityID() }
  /// The time zone times are printed in.
  var timeZone: TimeZone = .current

  struct Outcome: Hashable {
    let text: String
    /// 0 when it worked, 1 when it did not, 2 when the command was written wrong.
    let status: Int32
    var addsNewline = true

    var output: String { addsNewline ? text + "\n" : text }

    static func worked(_ text: String) -> Outcome { Outcome(text: text, status: 0) }
    static func failed(_ text: String) -> Outcome { Outcome(text: text, status: 1) }
  }

  func run(_ request: Request, json: Bool) async -> Outcome {
    do throws(Failure) {
      return try await carryOut(request, json: json)
    } catch {
      return .failed(error.message)
    }
  }

  private func carryOut(_ request: Request, json: Bool) async throws(Failure) -> Outcome {
    switch request {
    case .help(let topic): return Self.help(topic)
    case .recall(let text):
      let reply = try await line.run(Recall(text))
      if json { return .worked(Self.text(reply)) }
      let hits = try Failure.decoding([RecallHit].self, from: reply)
      guard !hits.isEmpty else { return .worked("Nothing said in a conversation or a run matches \"\(text)\".") }
      return .worked(hits.map { "\($0.path)\n    \($0.snippet)" }.joined(separator: "\n"))
    case .nameProject(let name, let icon):
      let reply = try await line.run(NameProject(name, icon: icon))
      if json { return .worked(Self.text(reply)) }
      let project = try Failure.decoding(Project.self, from: reply)
      return .worked("The project is named \(project.name ?? name).")
    case .iconProject(let icon):
      let reply = try await line.run(IconProject(icon))
      if json { return .worked(Self.text(reply)) }
      let project = try Failure.decoding(Project.self, from: reply)
      return .worked("The project icon is \(project.symbol).")
    case .describeProject(let line):
      let reply = try await self.line.run(DescribeProject(line))
      if json { return .worked(Self.text(reply)) }
      return .worked("The project's line: \(try Failure.decoding(Project.self, from: reply).summary)")
    case .search(let text): return try await search(text, json: json)
    case .show(let id): return try await show(id, json: json)
    case .read(let url):
      let reply = try await line.run(ReadSource(url: url))
      if json { return .worked(Self.text(reply)) }
      return Outcome(text: try Failure.decoding(String.self, from: reply), status: 0, addsNewline: false)
    case .repo(let url, let commit):
      let reply = try await line.run(FetchSourceRepository(url: url, commit: commit))
      if json { return .worked(Self.text(reply)) }
      let checkout = try Failure.decoding(SourceCheckout.self, from: reply)
      return .worked("\(checkout.path)\t\(checkout.commit)")
    case .save(let url): return saved(try await line.run(AddLink(url: url)), json: json)
    case .importFile(let path, let title): return try await importing(path, title: title, json: json)
    case .wait(let id): return try await wait(id, json: json)
    case .panel(let request): return try await panel(request, json: json)
    case .source(let request): return try await source(request, json: json)
    case .course(let request): return await course(request, json: json)
    case .schedule(let request): return try await schedule(request, json: json)
    case .followUp(let request): return try await followUp(request, json: json)
    case .next(let request): return try await next(request, json: json)
    case .follow(let request): return try await follow(request, json: json)
    case .connector(let request): return try await connector(request, json: json)
    case .feeling(let request):
      let reply = try await line.send(.feeling(request))
      return .worked(json ? Self.text(reply) : try Failure.decoding(String.self, from: reply))
    }
  }

  private func search(_ text: String, json: Bool) async throws(Failure) -> Outcome {
    let reply = try await line.run(Search(text: text, limit: 20))
    if json { return .worked(Self.text(reply)) }
    let hits = try Failure.decoding([SearchHit].self, from: reply)
    guard !hits.isEmpty else { return .worked("Nothing in the library matches \"\(text)\".") }
    let items = try Failure.decoding([Item].self, from: try await line.run(ListItems()))
    let titles = Dictionary(items.map { ($0.id, $0.title) }) { first, _ in first }
    return .worked(hits.map { Words.hit($0, titles: titles) }.joined(separator: "\n"))
  }

  private func show(_ id: EntityID, json: Bool) async throws(Failure) -> Outcome {
    let items = try Failure.decoding([Item].self, from: try await line.run(ListItems()))
    guard let item = items.first(where: { $0.id == id }) else { throw .host(.notFound(id.description)) }
    let feed = try await line.send(.follow(name: ItemJob.name, body: try Failure.encoding(ItemJob(item: id))))
    let folder = try await line.send(.itemFolder(id))
    if json {
      return .worked(
        [Self.text(try Failure.encoding(item)), Self.text(feed), Self.text(folder)].joined(separator: "\n"))
    }
    let job = try Self.job(in: feed)
    return .worked(Words.item(item, job: job, folder: try Failure.decoding(String.self, from: folder)))
  }

  private func importing(_ path: String, title: String?, json: Bool) async throws(Failure) -> Outcome {
    let file = (path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)).standardizedFileURL
    guard (try? file.checkResourceIsReachable()) == true else { throw .file("There is no file at \(path).") }
    guard isArticle(path) else {
      let upload = try await line.send(.upload(path: file.path(percentEncoded: false)))
      let reply = try await line.run(
        ImportMediaFile(upload: try Failure.decoding(Upload.self, from: upload), mode: .copy))
      return saved(reply, json: json)
    }
    let text: String
    do {
      text = try readText(file)
    } catch {
      throw .file("\(path) cannot be read: \(error.localizedDescription)")
    }
    let command = AddTextItem(
      fileName: file.lastPathComponent, text: text, title: title, authors: [Item.companionCredit])
    return saved(try await line.run(command), json: json)
  }

  private func wait(_ id: EntityID, json: Bool) async throws(Failure) -> Outcome {
    let body = try Failure.encoding(ItemJob(item: id))
    let feed = try await line.send(.follow(name: ItemJob.name, body: body)) { data in
      guard let feed = try? JSONDecoder().decode(Feed<Job?>.self, from: data) else { return true }
      guard case .value(let job?) = feed else { return true }
      return Words.isSettled(job.state)
    }
    let job = try Self.job(in: feed)
    let worked = job.map { $0.state == .done } ?? true
    let text = json ? Self.text(feed) : Words.outcome(of: job, item: id)
    return worked ? .worked(text) : .failed(text)
  }

  private func saved(_ reply: Data, json: Bool) -> Outcome {
    if json { return .worked(Self.text(reply)) }
    guard let item = try? JSONDecoder().decode(Item.self, from: reply) else { return .worked(Self.text(reply)) }
    return .worked(Words.saved(item))
  }

  private static func job(in feed: Data) throws(Failure) -> Job? {
    switch try Failure.decoding(Feed<Job?>.self, from: feed) {
    case .value(let job): return job
    case .unavailable(let error): throw .host(error)
    }
  }

  /// The overview, or one topic of it; it needs no app.
  static func help(_ topic: String?) -> Outcome {
    guard let topic else { return .worked(ToolGuide.text) }
    guard let text = ToolGuide.topic(topic) else {
      return .failed(
        "loci help has no topic \"\(topic)\". Topics: \(ToolGuide.topics.map(\.name).joined(separator: ", ")).")
    }
    return .worked(text)
  }

  static func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }

  /// A JSON array of these JSON values.
  static func list(_ values: [Data]) -> String {
    "[" + values.map(text).joined(separator: ",") + "]"
  }
}
