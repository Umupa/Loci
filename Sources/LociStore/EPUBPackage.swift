import Foundation
import LociModel

/// What an EPUB's package says: who wrote it, its chapters in reading order, its table of contents and cover.
struct EPUBPackage {
  let title: String?
  let authors: [String]
  let language: String?
  let chapters: [BookContents.Chapter]
  let toc: [BookContents.Entry]
  /// The path of the cover picture in the archive.
  let cover: String?

  /// Font obfuscation hides only the book's fonts, which Loci does not use; anything else is DRM.
  static let fontObfuscation: Set<String> = ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"]

  init(_ archive: BookArchive) throws(BookProblem) {
    guard let container = Self.tree("META-INF/container.xml", in: archive),
      let packagePath = container.first("rootfile")?.attribute("full-path")
    else { throw archive.contains("mimetype") ? .damaged : .notABook }
    if archive.contains("META-INF/rights.xml") { throw .protected }
    if archive.contains("META-INF/encryption.xml") {
      guard let encryption = Self.tree("META-INF/encryption.xml", in: archive) else { throw .protected }
      let methods = encryption.all("EncryptionMethod").compactMap { $0.attribute("Algorithm") }
      if methods.contains(where: { !Self.fontObfuscation.contains($0) }) { throw .protected }
    }
    guard let package = Self.tree(packagePath, in: archive) else { throw .damaged }
    let metadata = package.first("metadata")
    let fixed =
      metadata?.children("meta").contains {
        $0.attribute("property") == "rendition:layout" && $0.text == "pre-paginated"
      } == true
      || Self.tree("META-INF/com.apple.ibooks.display-options.xml", in: archive)?.all("option").contains {
        $0.attribute("name") == "fixed-layout" && $0.text == "true"
      } == true
    if fixed { throw .fixedLayout }

    let base = Self.folder(of: packagePath)
    var manifest: [String: (path: String, type: String, properties: Set<Substring>)] = [:]
    for item in package.first("manifest")?.children("item") ?? [] {
      guard let id = item.attribute("id"), let href = item.attribute("href") else { continue }
      manifest[id] = (
        Self.resolve(href, from: base).path, item.attribute("media-type") ?? "",
        Set((item.attribute("properties") ?? "").split(separator: " "))
      )
    }
    let spine = package.first("spine")
    let pages = (spine?.children("itemref") ?? []).compactMap { $0.attribute("idref").flatMap { manifest[$0] } }
      .filter { $0.type.contains("html") && archive.contains($0.path) }
    guard !pages.isEmpty else { throw .damaged }
    chapters = pages.map { BookContents.Chapter(path: $0.path, length: archive.size(of: $0.path) ?? 0) }

    title = metadata?.first("title").map(\.text).flatMap { $0.isEmpty ? nil : $0 }
    authors = metadata?.children("creator").map(\.text).filter { !$0.isEmpty } ?? []
    language = metadata?.first("language")?.text.split(separator: " ").first.map(String.init)
      .flatMap { $0.wholeMatch(of: /[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*/) == nil ? nil : $0 }

    let coverID = metadata?.children("meta").first { $0.attribute("name") == "cover" }?.attribute("content")
    cover =
      (manifest.values.first { $0.properties.contains("cover-image") }
      ?? coverID.flatMap { manifest[$0] }.flatMap { $0.type.hasPrefix("image/") ? $0 : nil })
      .map(\.path).flatMap { archive.contains($0) ? $0 : nil }

    let chapterIndex = Dictionary(chapters.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { first, _ in first })
    var toc: [BookContents.Entry] = []
    if let nav = manifest.values.first(where: { $0.properties.contains("nav") }),
      let tree = Self.tree(nav.path, in: archive)
    {
      let navs = tree.all("nav")
      if let list = (navs.first { $0.attribute("type")?.contains("toc") == true } ?? navs.first)?.first("ol") {
        toc = Self.entries(navList: list, depth: 0, from: Self.folder(of: nav.path), chapters: chapterIndex)
      }
    }
    if toc.isEmpty,
      let ncx =
        (spine?.attribute("toc").flatMap { manifest[$0] }
          ?? manifest.values.first { $0.type == "application/x-dtbncx+xml" }),
      let map = Self.tree(ncx.path, in: archive)?.first("navMap")
    {
      toc = Self.entries(navPoints: map, depth: 0, from: Self.folder(of: ncx.path), chapters: chapterIndex)
    }
    self.toc = toc.isEmpty ? chapters.indices.map { .init(title: String($0 + 1), depth: 0, chapter: $0) } : toc
  }

  private static func entries(navList list: XMLTree, depth: Int, from folder: String, chapters: [String: Int])
    -> [BookContents.Entry]
  {
    list.children("li").flatMap { item -> [BookContents.Entry] in
      let link = item.children("a").first
      let label = (link ?? item.children("span").first)?.text ?? ""
      var here: [BookContents.Entry] = []
      if let href = link?.attribute("href"), !label.isEmpty {
        let target = resolve(href, from: folder)
        if let chapter = chapters[target.path] {
          here = [.init(title: label, depth: depth, chapter: chapter, anchor: target.anchor)]
        }
      }
      let nested = item.children("ol").flatMap {
        entries(navList: $0, depth: depth + 1, from: folder, chapters: chapters)
      }
      return here + nested
    }
  }

  private static func entries(navPoints parent: XMLTree, depth: Int, from folder: String, chapters: [String: Int])
    -> [BookContents.Entry]
  {
    parent.children("navPoint").flatMap { point -> [BookContents.Entry] in
      let label = point.first("navLabel")?.text ?? ""
      var here: [BookContents.Entry] = []
      if let src = point.children("content").first?.attribute("src"), !label.isEmpty {
        let target = resolve(src, from: folder)
        if let chapter = chapters[target.path] {
          here = [.init(title: label, depth: depth, chapter: chapter, anchor: target.anchor)]
        }
      }
      return here + entries(navPoints: point, depth: depth + 1, from: folder, chapters: chapters)
    }
  }

  static func tree(_ path: String, in archive: BookArchive) -> XMLTree? {
    (try? archive.file(path)).flatMap(XMLTree.parse)
  }

  static func folder(of path: String) -> String {
    path.split(separator: "/", omittingEmptySubsequences: false).dropLast().joined(separator: "/")
  }

  /// A link inside the book as a path from the archive's root, and the anchor after `#`.
  static func resolve(_ href: String, from folder: String) -> (path: String, anchor: String?) {
    let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    let relative = String(parts[0]).removingPercentEncoding ?? String(parts[0])
    var components = folder.isEmpty ? [] : folder.split(separator: "/").map(String.init)
    for piece in relative.split(separator: "/") {
      switch piece {
      case ".": continue
      case "..": if !components.isEmpty { components.removeLast() }
      default: components.append(String(piece))
      }
    }
    let anchor = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
    return (components.joined(separator: "/"), anchor)
  }
}
