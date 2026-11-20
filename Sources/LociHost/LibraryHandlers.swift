import Foundation
import LociMedia
import LociModel
import LociStore

extension LocalHost {
  public func addLink(_ command: AddLink) async throws(HostError) -> Item {
    try await addLink(command, by: .person)
  }

  func addLink(_ command: AddLink, by saver: Saver) async throws(HostError) -> Item {
    let url = command.url
    let probe = await library.context.probes.take(url)
    let item = try attempt { try Self.item(at: url, probed: probe?.info, id: environment.newID(), why: command.why) }
    try attempt { try store.addPending(item) }
    do throws(HostError) {
      try attempt {
        if item.kind == .article, let html = command.articleHTML, html.utf8.count <= AddLink.maximumArticleBytes {
          _ = try store.saveWork(Data(html.utf8), named: JobRun.articleHTML, of: item.id)
        }
        if let probe {
          _ = try store.saveWork(probe.json, named: JobRun.info, of: item.id)
          if let cover = probe.cover { try store.saveCover(cover.data, extension: cover.fileExtension, of: item.id) }
        }
        if item.isMedia { try store.saveImportChoice(choosing(command.choice), of: item.id) }
      }
    } catch {
      try? store.deleteItem(item.id)
      throw error
    }
    await follow([.item(item.id)])
    if let first = Job.Stage.all(for: item, choice: library.context.choice(of: item.id)).first {
      await library.queue.begin(item.id, at: first)
    }
    await saved(item.id, by: saver)
    return item
  }

  /// The item a link starts as: what was probed behind it, or what its address tells.
  private static func item(at url: URL, probed info: MediaInfo?, id: EntityID, why: String?) throws -> Item {
    if let info {
      return try Item(
        id: id, kind: info.isAudio ? .audio(duration: info.duration) : .video(duration: info.duration),
        title: info.title, source: url, site: info.site, published: info.published.map(Timestamp.init), why: why)
    }
    let kind: Item.Kind =
      switch LinkKind(url) {
      case .video: .video(duration: nil)
      case .audio: .audio(duration: nil)
      case .paper: .paper
      case .article: .article
      }
    return try Item(id: id, kind: kind, title: LinkTitle.of(url), source: url, why: why)
  }

  /// The choice given, kept as the next default; the last one when none is given.
  private func choosing(_ given: ImportChoice?) throws -> ImportChoice {
    guard let given else { return library.context.lastChoice }
    try store.changeSettings { $0.importChoice = given }
    return given
  }

  public func importMediaFile(_ command: ImportMediaFile) async throws(HostError) -> Item {
    try await importMediaFile(command, by: .person)
  }

  func importMediaFile(_ command: ImportMediaFile, by saver: Saver) async throws(HostError) -> Item {
    guard let file = await hub.takeUpload(command.upload.id) else { throw .notFound("upload \(command.upload.id)") }
    let probe = await MediaProbe.of(file)
    let kind: Item.Kind
    if let probe {
      guard probe.hasSound else { throw .invalidRequest("\(file.lastPathComponent) has no sound") }
      kind = probe.hasPicture ? .video(duration: probe.duration) : .audio(duration: probe.duration)
    } else {
      switch LinkKind(file) {
      case .video: kind = .video(duration: nil)
      case .audio: kind = .audio(duration: nil)
      case .paper, .article: throw .invalidRequest("\(file.lastPathComponent) is not a video or audio file")
      }
    }
    let title = file.deletingPathExtension().lastPathComponent
    let item = try attempt {
      try Item(id: environment.newID(), kind: kind, title: title.isEmpty ? "Untitled" : title, why: command.why)
    }
    try attempt { try store.addPending(item) }
    do {
      try store.importMedia(file, as: command.mode, of: item.id)
      try store.saveImportChoice(choosing(command.choice), of: item.id)
    } catch {
      try? store.deleteItem(item.id)
      throw HostError(error)
    }
    await follow([.item(item.id)])
    if let first = Job.Stage.all(for: item, choice: library.context.choice(of: item.id)).first {
      await library.queue.begin(item.id, at: first)
    }
    await saved(item.id, by: saver)
    return item
  }

  public func retryJob(_ item: EntityID) async throws(HostError) -> Job {
    let store = store
    do {
      return try await library.queue.retry(item) { try JobRun.firstStage(of: try store.item(item), in: store) }
    } catch {
      throw HostError(error)
    }
  }

  public func pauseJob(_ item: EntityID) async throws(HostError) -> Done {
    await library.queue.pause(item)
    return Done()
  }

  public func savingBatch() async -> SavingBatch? {
    await library.queue.savingBatch
  }

  public func stopSaving() async throws(HostError) -> Int {
    let waiting = await library.queue.notStarted
    guard !waiting.isEmpty else { return 0 }
    _ = try await deleteItems(DeleteItems(waiting))
    return waiting.count
  }

  public func jobs() async throws(HostError) -> [Job] {
    await library.queue.all
  }

  public func job(of item: EntityID) async throws(HostError) -> Job? {
    await library.queue.job(of: item)
  }

  public func mediaPage(_ item: EntityID) async throws(HostError) -> MediaPage {
    try attempt {
      let transcript = try store.transcript(of: item)
      let translations = transcript.map { transcript in
        ((try? store.translations(of: item)) ?? []).filter { $0.fits(transcript) }
      }
      return MediaPage(
        transcript: transcript, translations: translations ?? [], outline: try? store.outline(of: item),
        hasCover: try store.coverFile(of: item) != nil, downloaded: try store.mediaFile(of: item) != nil)
    }
  }

  public func mediaFileInfo(of item: EntityID) async throws(HostError) -> MediaFileInfo {
    guard let info = try attempt({ try store.mediaFileInfo(of: item) }) else { throw .notFound("media of \(item)") }
    return info
  }

  public func mediaBytes(_ command: ReadMediaBytes) async throws(HostError) -> Data {
    try attempt { try store.mediaBytes(of: command.item, offset: command.offset, length: command.length) }
  }

  public func playback(_ command: ReadPlayback) async throws(HostError) -> Playback {
    let id = command.item
    if try attempt({ try store.mediaFile(of: id) }) != nil { return .downloaded }
    if !command.refresh, let stream = await library.context.streams.stream(for: id, at: environment.now()) {
      return .online(stream)
    }
    guard let source = try attempt({ try store.item(id) }).source else {
      throw .notFound("media of \(id)")
    }
    let context = library.context
    do throws(StageStop) {
      let tool = try await context.ytDlp(needing: [.ytDlp])
      let info: MediaInfo
      do {
        info = try await tool.resolve(source).info
      } catch {
        throw await context.stop(error, at: source)
      }
      await context.streams.keep(info.stream, for: id)
      guard let stream = info.stream else {
        throw StageStop.failed("this cannot be played online; it plays once downloaded", nil)
      }
      return .online(stream)
    } catch {
      switch error {
      case .wait(let need): throw .invalidRequest("waiting for \(need)")
      case .fail(let failure): throw .invalidRequest(failure.reason)
      }
    }
  }

  public func cover(of item: EntityID) async throws(HostError) -> Data? {
    try attempt { try store.cover(of: item) }
  }

  public func itemPDF(_ item: EntityID) async throws(HostError) -> Data {
    try attempt { try store.pdf(of: item) }
  }

  public func itemImage(_ command: ReadItemImage) async throws(HostError) -> Data {
    let name = command.name.hasPrefix("images/") ? String(command.name.dropFirst(7)) : command.name
    return try attempt { try store.image(named: name, of: command.item) }
  }
}

enum LinkTitle {
  /// What a link is called until its real title is known: the site and the path, as a person would read it.
  static func of(_ url: URL) -> String {
    let host = (url.host() ?? "").replacing(/^www\./, with: "")
    let path = url.path(percentEncoded: false)
    let query = url.query(percentEncoded: false).map { "?" + $0 } ?? ""
    let title = host + (path == "/" ? "" : path) + query
    return title.isEmpty ? url.absoluteString : title
  }
}
