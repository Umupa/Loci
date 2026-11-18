import CoreGraphics
import Foundation

/// What a PDF says about itself in its document information, when what it says looks meant for a reader.
struct PDFInfo: Hashable, Sendable {
  let title: String?
  let authors: [String]

  /// `nil` when the data is not a PDF that can be opened.
  init?(_ data: Data) {
    guard data.starts(with: Data("%PDF-".utf8)), let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider)
    else { return nil }
    guard let info = document.info else {
      title = nil
      authors = []
      return
    }
    title = Self.string("Title", in: info).flatMap(Self.readableTitle)
    authors = Self.string("Author", in: info).map(ArticleAssembler.authors) ?? []
  }

  private static func string(_ key: String, in dictionary: CGPDFDictionaryRef) -> String? {
    var value: CGPDFStringRef?
    guard CGPDFDictionaryGetString(dictionary, key, &value), let value,
      let text = CGPDFStringCopyTextString(value) as String?
    else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Word processors often leave a file name or their own name as the title.
  static func readableTitle(_ title: String) -> String? {
    let lowered = title.lowercased()
    let leftovers = ["microsoft word -", "untitled", ".doc", ".tex", ".dvi", ".pdf"]
    guard !leftovers.contains(where: lowered.contains), title.count > 2 else { return nil }
    return title
  }

  /// A title made from the last part of the address: `attention_is-all.pdf` reads `attention is all`.
  static func title(fromFileIn url: URL) -> String {
    let name =
      url.deletingPathExtension().lastPathComponent.removingPercentEncoding
      ?? url.deletingPathExtension().lastPathComponent
    let words = name.replacing(/[_\-+]+/, with: " ").trimmingCharacters(in: .whitespaces)
    return words.isEmpty ? (url.host() ?? url.absoluteString) : words
  }
}
