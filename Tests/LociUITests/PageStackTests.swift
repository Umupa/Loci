import Foundation
import LociModel
import SwiftUI
import Synchronization
import Testing

@testable import LociUI

@MainActor
struct PageStackTests {
  private final class Pages: Sendable {
    let seen = Mutex<[[Page]]>([])
  }

  private struct Opening: View {
    @Environment(\.openPage) private var openPage
    let next: Page

    var body: some View {
      Color.clear.onAppear { openPage(next) }
    }
  }

  private struct Stack: View {
    let first: Page
    let next: Page
    let pages: Pages
    @State private var path: [Page]

    init(first: Page, next: Page, pages: Pages) {
      self.first = first
      self.next = next
      self.pages = pages
      _path = State(initialValue: [first])
    }

    var body: some View {
      HStack {
        Color.clear
        PageStack(pages: $path) {
          Color.clear
        } destination: { page in
          if page == first { Opening(next: next) } else { Color.clear }
        }
      }
      .onChange(of: path) { pages.seen.withLock { $0.append(path) } }
    }
  }

  /// A link on a pushed page opens the next page over it. Beside a sidebar, as in the app: there the stack's
  /// own environment does not reach its pages.
  @Test func aPushedPageCanOpenTheNextOverItself() async throws {
    let first = Page.item(EntityID())
    let next = Page.item(EntityID())
    let pages = Pages()

    try await Snapshot.render(Stack(first: first, next: next, pages: pages), named: "page-stack", appearance: .light)

    #expect(pages.seen.withLock { $0.last } == [first, next])
  }
}
