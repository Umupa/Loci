import Foundation
import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// A text file the person dropped or chose. Only its name and contents go to the host, so a remote host
/// receives the same thing a local one does.
struct TextFile: Transferable, Equatable, Sendable {
  let fileName: String
  let text: String

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .text) { received in
      try TextFile(reading: received.file)
    }
  }

  init(reading url: URL) throws {
    let data = try Data(contentsOf: url)
    guard let text = String(data: data, encoding: .utf8) else { throw NotText() }
    fileName = url.lastPathComponent
    self.text = text
  }

  struct NotText: Error {}
}

/// What the start page's field holds, which decides what pressing return does.
enum PromptInput: Equatable {
  case empty
  case sentence(String)
  /// Goes into the library and opens.
  case link(URL)

  init(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      self = .empty
    } else if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
      ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false
    {
      self = .link(url)
    } else {
      self = .sentence(trimmed)
    }
  }
}
