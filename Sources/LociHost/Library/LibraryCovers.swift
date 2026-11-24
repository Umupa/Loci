import Foundation
import LociMedia
import LociModel
import LociStore

actor LibraryCovers {
  private let store: Store
  let finder: CoverFinder

  init(store: Store, network: any Network) {
    self.store = store
    finder = CoverFinder(network: network)
  }

  func keep(_ cover: FetchedFile, of item: EntityID) throws -> Bool {
    guard !Task.isCancelled, try store.coverFile(of: item) == nil else { return false }
    try store.saveCover(cover.data, extension: String(cover.name.dropFirst("cover.".count)), of: item)
    return true
  }

  func replace(_ item: EntityID, with file: URL) throws {
    try store.saveCover(copying: file, of: item)
  }
}

extension LibraryContext {
  func artwork(at source: URL, thumbnail: URL?, podcast: Bool) async -> FetchedFile? {
    if let thumbnail, let cover = await covers.finder.first(at: [thumbnail], referer: source) { return cover }
    if let cover = await covers.finder.webpage(at: source, includeBody: true) { return cover }
    return podcast ? await covers.finder.podcast(at: source) : nil
  }

  func bodyCover(of item: Item, at source: URL?) async -> FetchedFile? {
    guard let markdown = try? store.fetchedContent(of: item.id) else { return nil }
    return await covers.finder.body(markdown: markdown, at: source) { name in
      try? store.image(named: name, of: item.id)
    }
  }

  func backfillCovers(in folders: [URL]) async {
    for folder in folders {
      if Task.isCancelled { return }
      guard let item = store.itemForCoverBackfill(in: folder), (try? store.coverFile(of: item.id)) == nil
      else { continue }
      let cover: FetchedFile?
      switch item.kind {
      case .video, .audio:
        guard let source = item.source else { continue }
        let thumbnail: URL?
        if let json = try? store.workText(named: JobRun.info, of: item.id),
          let info = try? MediaInfo(json: Data(json.utf8))
        {
          thumbnail = info.thumbnail
        } else if let tool = try? await ytDlp(needing: [.ytDlp]) {
          thumbnail = try? await tool.resolve(source).info.thumbnail
        } else {
          thumbnail = nil
        }
        let podcast = if case .audio = item.kind { true } else { false }
        cover = await artwork(at: source, thumbnail: thumbnail, podcast: podcast)
      case .book:
        continue
      case .paper:
        guard let source = item.source else { continue }
        cover = await covers.finder.webpage(at: source, includeBody: true)
      case .article, .repository:
        if let source = item.source, let head = await covers.finder.webpage(at: source) {
          cover = head
        } else {
          cover = await bodyCover(of: item, at: item.source)
        }
      }
      if let cover, (try? await covers.keep(cover, of: item.id)) == true { await notify([.item(item.id)]) }
    }
    if !Task.isCancelled { try? store.markCoversBackfilled() }
  }
}
