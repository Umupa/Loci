import Foundation
import LociModel

/// Puts what a browser page holds into the library, signed in as the browser is: one video goes to the import
/// panel, anything else is added as a link, with the article as the page shows it when it has one. While the Mac
/// behind the window cannot take changes, it takes nothing.
@MainActor
struct PageTaker {
  let host: any LociModel.Host
  let session: BrowserSession
  let takeIn: TakeIn?
  let changesAllowed: Bool

  /// What the library took from a page, and why it would not take the rest.
  struct Taken: Equatable {
    var items: [EntityID] = []
    var refusal: HostError?
  }

  /// Hands the browser's sign-in to the host, so the import panel reads the videos as the reader sees them,
  /// then lets them wait in the panel.
  func takeVideos(_ links: [URL]) async {
    guard changesAllowed, let first = links.first else { return }
    await handOverSignIn(for: first)
    takeIn?.videos(links)
  }

  /// Keeps what was chosen from the page in `tab`: the page as it shows it, the papers as links, and the
  /// videos, the page among them when it is one, through the import panel. Tells what was added as links.
  func keep(_ chosen: [PageFinds.Find], from tab: BrowserTab) async -> Taken {
    guard changesAllowed else { return Taken() }
    var taken = Taken()
    let pageIsVideo = tab.address.map { LinkKind($0) == .video } ?? false
    if chosen.contains(where: { $0.kind == .page }), !pageIsVideo, let address = tab.address {
      let html = await tab.articleHTML(at: address)
      await add(AddLink(url: address, articleHTML: html), to: &taken)
    }
    for paper in chosen where paper.kind == .paper {
      await add(AddLink(url: paper.url), to: &taken)
    }
    let videos = chosen.filter { $0.kind == .video || ($0.kind == .page && pageIsVideo) }.map(\.url)
    if !videos.isEmpty { await takeVideos(videos) }
    return taken
  }

  private func add(_ link: AddLink, to taken: inout Taken) async {
    await handOverSignIn(for: link.url)
    do throws(HostError) {
      taken.items.append(try await host.run(link).id)
    } catch {
      taken.refusal = error
    }
  }

  private func handOverSignIn(for link: URL) async {
    let cookies = await session.cookies(for: link)
    if !cookies.isEmpty { _ = try? await host.run(HandOverBrowserCookies(cookies)) }
  }
}
