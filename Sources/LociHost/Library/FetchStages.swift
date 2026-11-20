import Foundation
import LociMedia
import LociModel
import LociStore

/// Resolving a link and downloading what is behind it.
extension JobRun {
  /// Reads the title, cover, chapters and the site's own subtitles, and remembers where to play from. What
  /// the import panel read a moment ago is used rather than reading the page again.
  func resolve(_ item: Item) async throws(StageStop) {
    guard let source = item.source else { return }
    let tool = try await context.ytDlp(needing: [.ytDlp])
    let probed = try stored { try context.store.workFile(named: Self.info, of: item.id) }
      .flatMap { try? Data(contentsOf: $0) }
    if let probed, let info = try? MediaInfo(json: probed) {
      try await adopt(info, json: probed, of: item, using: tool)
      return
    }
    let (info, json): (MediaInfo, Data)
    do {
      (info, json) = try await tool.resolve(source)
    } catch {
      throw await context.stop(error, at: source)
    }
    try await adopt(info, json: json, of: item, using: tool)
  }

  /// Asks yt-dlp about a link read as an article, and makes it a video or episode when a site it knows has
  /// one there. Whether it did. Without yt-dlp, or when no site it knows has media there, the item is left be.
  func recognize(_ item: Item) async throws(StageStop) -> Bool {
    guard case .article = item.kind, let source = item.source,
      let tool = try? await context.ytDlp(needing: [.ytDlp])
    else { return false }
    let recognized: (info: MediaInfo, json: Data)?
    do {
      recognized = try await tool.recognize(source)
    } catch  where error.kind == .needsLogin {
      throw await context.stop(error, at: source)
    } catch {
      return false
    }
    guard let recognized else { return false }
    if context.choice(of: item.id) == nil {
      try stored { try context.store.saveImportChoice(context.lastChoice, of: item.id) }
    }
    try await adopt(recognized.info, json: recognized.json, of: item, using: tool)
    return true
  }

  /// Keeps what yt-dlp read behind the link: where to play from, the title, cover, chapters and subtitles.
  private func adopt(_ info: MediaInfo, json: Data, of item: Item, using tool: YtDlp) async throws(StageStop) {
    guard let source = item.source else { return }
    await context.streams.keep(info.stream, for: item.id)
    _ = try? context.store.saveWork(json, named: Self.info, of: item.id)
    let resolved = try stored {
      try Item(
        id: item.id, kind: info.isAudio ? .audio(duration: info.duration) : kind(of: item, duration: info.duration),
        title: info.title, authors: item.authors, source: source, language: item.language,
        contentHash: item.contentHash, site: info.site ?? item.site, published: info.published.map(Timestamp.init),
        why: item.why)
    }
    await saveCover(from: info.thumbnail)
    try stored { try context.store.retitle(resolved, from: item.title) }
    await context.notify([.item(item.id)])
    if !info.chapters.isEmpty, try stored({ try context.store.outline(of: item.id) }) == nil {
      try stored { try context.store.save(try Outline(chapters: info.chapters), of: item.id) }
    }
    let choice = context.choice(of: item.id)
    guard choice?.siteSubtitles ?? true else { return }
    let preferred = choice?.subtitleLanguage.flatMap { info.subtitleLanguages.contains($0) ? $0 : nil }
    if let language = preferred ?? info.subtitleLanguage,
      try stored({ try context.store.transcript(of: item.id) }) == nil
    {
      await saveSubtitles(language, using: tool)
    }
  }

  /// Downloads the media at the chosen quality in the background while it plays online, picking up a part
  /// already downloaded. Sound fetched for recognition is kept as it is when only sound is wanted.
  func download(_ item: Item) async throws(StageStop) {
    guard try stored({ try context.store.mediaFile(of: item.id) }) == nil, let source = item.source else { return }
    let quality = context.choice(of: item.id)?.quality ?? .hd1080
    let audio: Bool = if case .audio = item.kind { true } else { quality == .audio }
    let heard = try stored { try context.store.workFile(named: Self.sound, of: item.id) }
    let file: URL
    if audio, let heard {
      file = heard
    } else {
      let tool = try await context.ytDlp(needing: [.ytDlp, .ffmpeg])
      file = try await fetch(
        source, audio: audio, height: quality.height ?? 1080, using: tool, at: .download, report: downloadProgress())
    }
    let media = try stored { try context.store.adoptMedia(file, of: item.id) }
    try stored { try context.store.clearWork(of: item.id) }
    await context.notify([.item(item.id)])
    guard item.duration == nil, let probe = await MediaProbe.of(media), let duration = probe.duration else { return }
    let timed = try stored {
      try Item(
        id: item.id, kind: kind(of: item, duration: duration), title: item.title, authors: item.authors,
        source: item.source, language: item.language, contentHash: item.contentHash, site: item.site,
        published: item.published, why: item.why)
    }
    try stored { try context.store.save(timed) }
  }

  /// Downloads into the work folder in turn with other downloads, from what was read behind the link.
  func fetch(
    _ source: URL, audio: Bool, height: Int = 1080, using tool: YtDlp, at stage: Job.Stage,
    report: @escaping @Sendable (Fraction?, Job.Amount?) -> Void
  ) async throws(StageStop) -> URL {
    let folder = try stored { try context.store.workFolder(of: item) }
    let read = try stored { try context.store.workFile(named: Self.info, of: item) }
    let context = context
    return try await inTurn(queue.gates.downloads, at: stage) { () async throws(StageStop) -> URL in
      do throws(MediaError) {
        return try await tool.download(
          source, info: read, audio: audio, height: height, into: folder, progress: report)
      } catch {
        throw await context.stop(error, at: source)
      }
    }
  }

  private func kind(of item: Item, duration: Duration?) -> Item.Kind {
    if case .audio = item.kind { return .audio(duration: duration) }
    return .video(duration: duration)
  }

  /// Saved before the resolved item is announced: the window reads an item's cover once per version of the
  /// item, and the cover's arrival alone does not change the item. A cover that cannot be had is left out.
  private func saveCover(from thumbnail: URL?) async {
    guard (try? context.store.coverFile(of: item)) == nil, let cover = await context.cover(at: thumbnail) else {
      return
    }
    try? context.store.saveCover(cover.data, extension: cover.fileExtension, of: item)
  }

  /// Subtitles that cannot be had are left to recognition.
  private func saveSubtitles(_ language: String, using tool: YtDlp) async {
    guard let folder = try? context.store.workFolder(of: item),
      let file = try? await tool.subtitles(info: folder.appending(path: Self.info), language: language, into: folder),
      let text = try? context.store.workText(named: file.lastPathComponent, of: item)
    else { return }
    let segments = Subtitles.segments(fromWebVTT: text)
    guard !segments.isEmpty,
      let transcript = try? Transcript(
        language: Self.tag(language), origin: .platform, segments: segments)
    else { return }
    try? context.store.save(transcript, of: item)
    await context.notify([.item(item)])
  }

  /// What yt-dlp read behind the link, kept in the work folder until the download is done.
  static let info = "info.json"
  /// The sound fetched to recognize speech in, before or instead of the media.
  static let sound = "media.m4a"

  /// A BCP 47 tag from a site's language code, which may carry extras such as `en-orig`.
  static func tag(_ code: String) -> String? {
    let tag = code.replacingOccurrences(of: "_", with: "-")
    return tag.wholeMatch(of: /[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*/) != nil ? tag : nil
  }
}

extension Item {
  var isMedia: Bool {
    switch kind {
    case .video, .audio: true
    case .article, .paper, .repository: false
    }
  }

  var duration: Duration? {
    switch kind {
    case .video(let duration), .audio(let duration): duration
    case .article, .paper, .repository: nil
    }
  }
}
