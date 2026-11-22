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
  let failed: (HostError) -> Void
  let changesAllowed: Bool

  /// Hands the browser's sign-in to the host, so the import panel reads the videos as the reader sees them,
  /// then lets them wait in the panel.
  func takeVideos(_ links: [URL]) async {
    guard changesAllowed, let first = links.first else { return }
    await handOverSignIn(for: first)
    takeIn?.videos(links)
  }

  /// Adds the page in `tab` as it shows it, staying on the page; its button then shows it in the library.
  func addPage(in tab: BrowserTab) async {
    guard changesAllowed, let address = tab.address else { return }
    let html = await tab.articleHTML(at: address)
    await handOverSignIn(for: address)
    do throws(HostError) {
      _ = try await host.run(AddLink(url: address, articleHTML: html))
    } catch {
      failed(error)
    }
  }

  private func handOverSignIn(for link: URL) async {
    let cookies = await session.cookies(for: link)
    if !cookies.isEmpty { _ = try? await host.run(HandOverBrowserCookies(cookies)) }
  }
}
