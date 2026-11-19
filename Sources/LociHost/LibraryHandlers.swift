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
    let kind: Item.Kind =
      switch LinkKind(url) {
      case .video: .video(duration: nil)
      case .audio: .audio(duration: nil)
      case .paper: .paper
      case .article: .article
      }
    let item = try attempt { try Item(id: environment.newID(), kind: kind, title: LinkTitle.of(url), source: url) }
    try attempt { try store.addPending(item) }
    await follow([.item(item.id)])
    if let first = Job.Stage.all(for: item).first { await library.queue.begin(item.id, at: first) }
    await saved(item.id, by: saver)
    return item
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
    let item = try attempt { try Item(id: environment.newID(), kind: kind, title: title.isEmpty ? "Untitled" : title) }
    try attempt { try store.addPending(item) }
    do {
      try store.importMedia(file, as: command.mode, of: item.id)
    } catch {
      try? store.deleteItem(item.id, notes: .delete)
      throw HostError(error)
    }
    await follow([.item(item.id)])
    await library.queue.begin(item.id, at: .transcribe)
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

  public func cancelJob(_ item: EntityID) async throws(HostError) -> Done {
    await library.queue.cancel(item)
    return Done()
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
