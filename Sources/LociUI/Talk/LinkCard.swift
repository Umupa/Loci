import AppKit
import LociModel
import SwiftUI

/// Link previews the window has already read from the host, so scrolling back does not ask again.
@MainActor
@Observable
final class LinkPreviews {
  private var previews: [URL: LinkPreview] = [:]
  private var images: [URL: NSImage] = [:]
  private var asked: Set<URL> = []

  func preview(of url: URL) -> LinkPreview? { previews[url] }
  func image(of url: URL) -> NSImage? { images[url] }

  func load(_ url: URL, from host: any LociModel.Host) async {
    guard asked.insert(url).inserted else { return }
    guard let preview = try? await host.run(ReadLinkPreview(url: url)) else {
      asked.remove(url)
      return
    }
    previews[url] = preview
    guard preview.image != nil, let data = try? await host.run(ReadLinkImage(url: url)) ?? nil,
      let image = NSImage(data: data)
    else { return }
    images[url] = image
  }
}

extension EnvironmentValues {
  /// Set by the window; a card outside one keeps its own.
  @Entry var linkPreviews: LinkPreviews?
}

/// A link Loci gave, as a card: the page's picture, its title, and the site with what the page says it is.
/// Without a picture, only the title and the site.
struct LinkCard: View {
  @Environment(\.host) private var host
  @Environment(\.linkPreviews) private var shared
  @State private var own = LinkPreviews()
  let url: URL
  var showsWords = true

  var body: some View {
    let previews = shared ?? own
    let preview = previews.preview(of: url)
    let site = preview?.site ?? url.host() ?? url.absoluteString
    let title = Text(verbatim: preview?.title ?? LinkCard.title(of: url))
    Group {
      if preview?.image != nil {
        CardShell(title: title, source: source(site, preview?.summary), showsWords: showsWords) {
          if let image = previews.image(of: url) {
            Image(nsImage: image).resizable().scaledToFill()
          }
        }
      } else {
        CardShell(title: title, source: Text(verbatim: site), showsWords: showsWords)
      }
    }
    .task(id: url) { await previews.load(url, from: host) }
  }

  private func source(_ site: String, _ summary: String?) -> Text {
    Text(verbatim: [site, summary].compactMap { $0 }.joined(separator: " · "))
  }

  /// What a link is called until its page says: the path after the site, as a person would read it.
  static func title(of url: URL) -> String {
    let path = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return path.isEmpty ? url.host() ?? url.absoluteString : path
  }
}

extension CardShell {
  /// A card whose picture is drawn by `picture`.
  init(title: Text, source: Text?, showsWords: Bool = true, @ViewBuilder picture: () -> Picture) {
    self.init(title: title, source: source, showsWords: showsWords, picture: picture())
  }
}

/// Opens a link in the built-in browser and goes there.
@MainActor
struct OpenLink {
  let browser: BrowserSession?
  let openPlace: OpenPlace

  func callAsFunction(_ url: URL) {
    browser?.open(url)
    openPlace(.browser)
  }
}

/// Links Loci gave one after another: a single card, or a stack that spreads into a grid. A card opens its page
/// over the conversation, or in the browser where nothing opens it over what is shown.
struct LinkCards: View {
  @Environment(\.browser) private var browser
  @Environment(\.openPlace) private var openPlace
  @Environment(\.peekLink) private var peekLink
  let links: [URL]
  var spread = false

  var body: some View {
    let open = OpenLink(browser: browser, openPlace: openPlace)
    CardStack(cards: links, spread: spread) { url, front in
      LinkCard(url: url, showsWords: front)
    } open: { url in
      if let peekLink { peekLink(url) } else { open(url) }
    }
  }
}
