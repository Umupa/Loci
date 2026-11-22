import Foundation
import LociMedia
import LociModel
import LociStore

extension JobRun {
  static let articleHTML = "article.html"

  func fetchPage(_ item: Item) async throws(StageStop) -> ArticlePage? {
    guard let source = item.source,
      try stored({ try context.store.fetchedContent(of: item.id) }) == nil
    else { return nil }
    let html = try stored { try context.store.workText(named: Self.articleHTML, of: item.id) }
    if html == nil, try await recognize(item) { return nil }
    guard let fetcher = context.media.textFetching else {
      throw .failed("Fetching articles is not available in this build.")
    }
    let page = try await fetch(source) { () async throws(FetchError) in
      try await fetcher.articlePage(at: source, html: html)
    }
    guard !Task.isCancelled else { return nil }
    if let title = page.preview.title {
      let preview = try stored {
        try Item(
          id: item.id, kind: .article, title: title, authors: item.authors, source: source,
          language: item.language, contentHash: item.contentHash, site: page.preview.site,
          published: item.published, why: item.why)
      }
      try stored { try context.store.retitle(preview, from: item.title) }
      await context.notify([.item(item.id)])
    }
    if try stored({ try context.store.coverFile(of: item.id) }) == nil,
      let cover = await context.covers.finder.first(at: page.coverImages, referer: page.preview.url),
      try await keepCover(cover)
    {
      await context.notify([.item(item.id)])
    }
    return page
  }

  func extract(_ item: Item, page: ArticlePage?) async throws(StageStop) {
    guard let source = item.source else { return }
    if item.kind == .paper {
      try await extractPaper(item, at: source)
      return
    }
    guard try stored({ try context.store.fetchedContent(of: item.id) }) == nil else { return }
    let loaded: ArticlePage?
    if let page { loaded = page } else { loaded = try await fetchPage(item) }
    guard let loaded else { return }
    let article = try await fetch(source) { () async throws(FetchError) in try await loaded.article() }
    guard !Task.isCancelled else { return }
    let current = try stored { try context.store.item(item.id) }
    let fetched = try stored {
      try Item(
        id: item.id, kind: .article, title: article.title, authors: article.authors, source: source,
        language: article.language.flatMap(Self.tag), site: article.site ?? current.site,
        published: article.published.map(Timestamp.init), why: current.why)
    }
    let images = Dictionary(article.images.map { ($0.name, $0.data) }, uniquingKeysWith: { first, _ in first })
    try stored {
      try context.store.retitle(fetched, from: current.title)
      try context.store.saveArticle(article.markdown, images: images, of: item.id)
    }
  }

  func findCover(_ item: Item, page: ArticlePage?) async throws(StageStop) {
    if let source = page?.preview.url ?? item.source,
      try stored({ try context.store.coverFile(of: item.id) }) == nil,
      let cover = await context.bodyCover(of: item, at: source)
    {
      _ = try await keepCover(cover)
    }
    if !Task.isCancelled { try stored { try context.store.removeWork(named: Self.articleHTML, of: item.id) } }
  }

  private func keepCover(_ cover: FetchedFile) async throws(StageStop) -> Bool {
    do {
      return try await context.covers.keep(cover, of: item)
    } catch {
      throw .failed(Self.describe(HostError(error)))
    }
  }

  private func extractPaper(_ item: Item, at source: URL) async throws(StageStop) {
    guard let fetcher = context.media.textFetching else {
      throw .failed("Fetching papers is not available in this build.")
    }
    let paper = try await fetch(source) { () async throws(FetchError) in try await fetcher.paper(at: source) }
    guard !Task.isCancelled else { return }
    let fetched = try stored {
      try Item(
        id: item.id, kind: .paper, title: paper.title, authors: paper.authors, source: source,
        language: item.language, site: item.site, published: paper.published.map(Timestamp.init), why: item.why)
    }
    try stored {
      try context.store.savePDF(paper.pdf, of: item.id)
      try context.store.retitle(fetched, from: item.title)
    }
    if try stored({ try context.store.coverFile(of: item.id) }) == nil,
      let cover = await context.covers.finder.webpage(at: source, includeBody: true)
    {
      _ = try await keepCover(cover)
    }
  }

  private func fetch<Value>(_ source: URL, _ body: () async throws(FetchError) -> Value) async throws(StageStop)
    -> Value
  {
    do {
      return try await body()
    } catch {
      if error.needsLogin { throw .wait(.login(site: source.host() ?? source.absoluteString)) }
      throw .failed(error.reason, .retry, error.cause)
    }
  }
}
