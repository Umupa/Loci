import AppKit
import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// What a drag from Finder, a browser or another app brings that Loci can add.
enum Dropped: Equatable, Sendable {
  case link(URL)
  case textFile(TextFile)
  /// A video or audio file on this Mac.
  case mediaFile(URL)

  /// The kinds of drag a page accepts: a file, a link, or text that is a link.
  static let types: [UTType] = [.fileURL, .url, .plainText]

  /// Starts reading each dragged thing during the drop, while it can still be read: a video or audio file as
  /// itself, another file as a text file, a link as itself, text when it holds one link. Anything else comes
  /// to nothing.
  static func reading(_ providers: [NSItemProvider]) -> [AsyncStream<Dropped>] {
    providers.map(reading)
  }

  /// What was read, in the order it was dragged.
  static func collect(_ reading: [AsyncStream<Dropped>]) async -> [Dropped] {
    var dropped: [Dropped] = []
    for stream in reading {
      for await one in stream { dropped.append(one) }
    }
    return dropped
  }

  private static func reading(_ provider: NSItemProvider) -> AsyncStream<Dropped> {
    let (stream, continuation) = AsyncStream.makeStream(of: Dropped.self)
    func load<Value: Transferable>(_ type: Value.Type, as made: @escaping @Sendable (Value) -> Dropped?) {
      _ = provider.loadTransferable(type: type) { result in
        if let value = try? result.get(), let dropped = made(value) { continuation.yield(dropped) }
        continuation.finish()
      }
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      load(URL.self) { file in
        guard file.isFileURL else { return nil }
        if isMedia(file) { return .mediaFile(file) }
        return (try? TextFile(reading: file)).map(Dropped.textFile)
      }
    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      load(URL.self) { url in url.isWebLink ? .link(url) : nil }
    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      load(String.self) { text in link(in: text).map(Dropped.link) }
    } else {
      continuation.finish()
    }
    return stream
  }

  static func isMedia(_ file: URL) -> Bool {
    UTType(filenameExtension: file.pathExtension)?.conforms(to: .audiovisualContent) == true
  }

  /// Text that is a link, or holds exactly one among other words.
  static func link(in text: String) -> URL? {
    if let url = URL(webLinkText: text) { return url }
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    let links = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
      .filter(\.isWebLink)
    return links.count == 1 ? links[0] : nil
  }
}

extension View {
  /// A text, video or audio file or a link dropped anywhere on the view is taken in, staying on the page. While
  /// something is dragged over it the view is outlined in amber.
  func acceptingDrops() -> some View {
    modifier(AcceptingDrops())
  }
}

private struct AcceptingDrops: ViewModifier {
  @Environment(\.takeIn) private var takeIn
  @State private var targeted = false

  func body(content: Content) -> some View {
    content
      .overlay {
        if targeted {
          RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Palette.accent.opacity(0.06))
            .strokeBorder(Palette.accent, lineWidth: 2)
            .padding(Spacing.xs)
            .allowsHitTesting(false)
        }
      }
      .onDrop(of: takeIn == nil ? [] : Dropped.types, isTargeted: $targeted) { providers in
        let reading = Dropped.reading(providers)
        Task { @MainActor in takeIn?.dropped(await Dropped.collect(reading)) }
        return true
      }
  }
}
