import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing
import WebKit

@testable import LociUI

/// BK-S5, BK-S6, BK-S11: a book's pages and the library's books, in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct BookSnapshots {
  static func shoot(
    _ name: String, at place: WindowState, appearance: Snapshot.Appearance,
    size: CGSize = LibrarySnapshots.window, english: Bool = false
  ) async throws {
    let books = try SampleBooks()
    let activity = Activity()
    let view = MachineWindow(memory: WindowMemory(recall: { place }, remember: { _ in }))
      .lociHost(
        FakeHost(
          try Sample(problems: false), library: try SampleLibrary().withBooks(books), activity: activity,
          books: books)
      )
      .defaultAppStorage(LibrarySnapshots.defaults(panel: false))
    let quiet = Quiet(activity)
    let file = try await Snapshot.render(
      view, named: name, size: size, appearance: appearance, locale: Locale(identifier: english ? "en" : "zh-Hans"),
      until: { window in quiet.settled() && Self.pagesLaidOut(in: window) }, steady: true)
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  /// No book page, or one whose chapter has finished loading.
  static func pagesLaidOut(in window: NSWindow) -> Bool {
    func find(_ view: NSView) -> WKWebView? {
      (view as? WKWebView) ?? view.subviews.lazy.compactMap(find).first
    }
    guard let content = window.contentView, let page = find(content) else { return true }
    return page.url != nil && !page.isLoading
  }

  static func reading(_ item: EntityID) -> WindowState {
    WindowState(place: .library(.book), pages: [.item(item)])
  }

  /// BK-S5, BK-S6: two pages of 孔乙己 side by side; the book's white table and red text give way to the paper.
  @Test(arguments: Snapshot.Appearance.allCases)
  func twoPages(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("book-pages", at: Self.reading(try SampleBooks().nahan.id), appearance: appearance)
  }

  /// BK-S5: one page in a narrow window, an English book with a picture on paper.
  @Test(arguments: Snapshot.Appearance.allCases)
  func onePage(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "book-one-page", at: Self.reading(try SampleBooks().meditations.id), appearance: appearance,
      size: CGSize(width: 820, height: 760), english: true)
  }

  /// BK-S11: the library's books, read most recently first, with covers, authors and how far in.
  @Test(arguments: Snapshot.Appearance.allCases)
  func library(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("book-library", at: WindowState(place: .library(.book)), appearance: appearance)
  }

  /// BK-S9: the reading settings, their size glyphs drawn as aA in Chinese too.
  @Test(arguments: Snapshot.Appearance.allCases)
  func settings(appearance: Snapshot.Appearance) async throws {
    let form = BookSettingsForm(size: .constant(18), spacing: .constant(.normal), face: .constant(.serif))
      .background(Palette.surface)
    let file = try await Snapshot.render(
      form, named: "book-settings", size: CGSize(width: 240, height: 150), appearance: appearance)
    #expect(try Data(contentsOf: file).count > 1_000)
  }
}
