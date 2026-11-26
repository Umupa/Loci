import AppKit
import Foundation
import LociModel
import Testing

@testable import LociUI

/// H-S8: the library button beside the browser's address while a page is saved, once it is, and when it was
/// not, in light and dark, in Chinese and English.
@MainActor
@Suite(.serialized, .onStage)
struct KeepSnapshots {
  enum Moment: String, CaseIterable {
    case saving, saved, stopped
  }

  @Test(arguments: Moment.allCases, Snapshot.Appearance.allCases)
  func keptFromTheBrowser(moment: Moment, appearance: Snapshot.Appearance) async throws {
    try await shoot(moment, appearance, english: false)
  }

  @Test(arguments: Moment.allCases)
  func keptFromTheBrowserInEnglish(moment: Moment) async throws {
    try await shoot(moment, .light, english: true)
  }

  private func shoot(_ moment: Moment, _ appearance: Snapshot.Appearance, english: Bool) async throws {
    var library = try SampleLibrary()
    let article = library.article
    var keeping = Keeping(chosen: [])
    switch moment {
    case .saving:
      keeping.took([article.id], refusal: nil)
      library.jobs = [Job(item: article.id, stage: .fetchPage, state: .running(progress: Fraction(0.35)))]
    case .saved:
      keeping.took([article.id], refusal: nil)
      library.jobs = []
    case .stopped:
      keeping.took([article.id], refusal: nil)
      library.jobs = [
        Job(
          item: article.id, stage: .extract,
          state: .failed(Job.Failure(reason: "The page has no text to read.", remedy: .retry, cause: .noArticleText)))
      ]
    }
    let browser = BrowserSession()
    browser.open(URL(string: "https://notebook.tines.com/writing/anatomy-of-a-3b-step/"))
    browser.current.learn(PageFacts(hasArticle: true))
    try await LibrarySnapshots.shoot(
      "browser-keep-\(moment.rawValue)\(english ? "-en" : "")", library, at: WindowState(place: .browser),
      appearance: appearance,
      standIns: StandIns(webPage: LibrarySnapshots.webPage("article", appearance), keeping: keeping), browser: browser,
      english: english)
  }
}
