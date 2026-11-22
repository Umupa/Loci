import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

@MainActor
@Suite(.serialized, .onStage)
struct LibraryRenderingTests {
  @Test func a244ItemGalleryBuildsOnlyCardsNearTheViewport() async throws {
    try await scroll(.gallery)
  }

  @Test func a244ItemListBuildsOnlyRowsNearTheViewport() async throws {
    try await scroll(.list)
  }

  @Test func aListRowRequestsOnlyItsFortyPointCover() async throws {
    let size = CGSize(width: 600, height: 180)
    let library = try SampleLibrary()
    let covers = Covers()
    let view = ScrollView {
      LibraryList { LibraryRow(item: library.video, reading: nil, chosen: false, renamed: nil) }
    }
    .environment(\.covers, covers)
    .environment(\.displayScale, 2)
    .lociHost(FakeHost(try Sample(problems: false), library: library))
    let window = Self.window(view, size: size)
    defer { window.orderOut(nil) }

    try await eventually("the list thumbnail") { covers.image(of: library.video.id) != nil }
    let image = try #require(covers.image(of: library.video.id))
    #expect(max(image.size.width, image.size.height) == 80)
  }

  private func scroll(_ presentation: LibraryPresentation) async throws {
    let visits = Visits()
    let ids = Array(0..<244)
    var entropy = Sample.Seeded()
    let cards = ids.map { index in
      GalleryPlacement.Tile(
        id: EntityID(at: Date(timeIntervalSince1970: Double(index)), entropy: &entropy),
        kind: index.isMultiple(of: 3) ? .audio : .video,
        busy: index.isMultiple(of: 19))
    }
    let indexByID = Dictionary(uniqueKeysWithValues: zip(cards.map(\.id), ids))
    let size = CGSize(width: 900, height: 600)
    let content = ScrollView {
      VStack(spacing: 0) {
        Color.clear.frame(height: 92)
        switch presentation {
        case .gallery:
          LibraryGallery(tiles: cards) { id, _ in
            if let index = indexByID[id] { Cell(index: index, visits: visits) }
          }
        case .list:
          LibraryList {
            ForEach(ids, id: \.self) { Cell(index: $0, visits: visits).frame(height: 54) }
          }
        }
      }
    }
    let window = Self.window(content, size: size)
    defer { window.orderOut(nil) }
    let hosting = try #require(window.contentView)

    try await eventually("the first page to have a scroll range") {
      guard let scroll = Self.scrollView(in: hosting) else { return false }
      return scroll.documentView?.frame.height ?? 0 > 10_000 && visits.built.contains(0)
    }
    #expect(visits.built.count < 48, "built \(visits.built.count) of \(ids.count) items at the top")
    #expect(!visits.built.contains(243))

    let scroll = try #require(Self.scrollView(in: hosting))
    let document = try #require(scroll.documentView)
    scroll.contentView.scroll(to: CGPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
    scroll.reflectScrolledClipView(scroll.contentView)

    try await eventually("the last item to be built") { visits.built.contains(243) }
    #expect(visits.built.count < 96, "built \(visits.built.count) of \(ids.count) items across both pages")
    #expect(!visits.built.contains(122))
  }

  private static func window(_ view: some View, size: CGSize) -> NSWindow {
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    window.orderBack(nil)
    return window
  }

  private static func scrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { Self.scrollView(in: $0) }.first
  }

  private final class Visits {
    var built: Set<Int> = []
  }

  private struct Cell: View {
    let index: Int
    let visits: Visits

    init(index: Int, visits: Visits) {
      self.index = index
      self.visits = visits
      visits.built.insert(index)
    }

    var body: some View {
      Text(verbatim: "Item \(index)").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
