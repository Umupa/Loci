import Foundation
import LociModel

/// The files of articles and papers: `content.md` with its pictures under `images/`, and `content.pdf`.
extension Store {
  static let pdfFile = "content.pdf"
  static let imagesFolder = "images"

  /// Writes an article's text and its pictures, named as the text refers to them (`images/<name>`).
  public func saveArticle(_ markdown: String, images: [String: Data], of item: EntityID) throws {
    let folder = try itemFolder(item)
    for (name, data) in images {
      try write(data, to: folder.appending(path: Self.imagesFolder).appending(path: try Self.plainName(name)))
    }
    try write(Data(markdown.utf8), to: folder.appending(path: Self.contentFile))
  }

  /// `nil` while the text is still being fetched.
  public func fetchedContent(of item: EntityID) throws -> String? {
    try existing(itemFolder(item).appending(path: Self.contentFile)).map(readText)
  }

  public func savePDF(_ data: Data, of item: EntityID) throws {
    try write(data, to: itemFolder(item).appending(path: Self.pdfFile))
  }

  public func pdf(of item: EntityID) throws -> Data {
    try read(itemFolder(item).appending(path: Self.pdfFile))
  }

  /// A picture of an article by the name the text uses for it. Only names inside `images/` are read.
  public func image(named name: String, of item: EntityID) throws -> Data {
    try read(itemFolder(item).appending(path: Self.imagesFolder).appending(path: try Self.plainName(name)))
  }

  static func plainName(_ name: String) throws -> String {
    guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != "..", !name.hasPrefix(".")
    else { throw StoreError.invalid(FileProblem(path: name, kind: .invalid, reason: "not a plain file name")) }
    return name
  }
}
