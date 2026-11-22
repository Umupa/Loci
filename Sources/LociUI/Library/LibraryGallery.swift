import LociModel
import SwiftUI

/// Positions cards in library order and builds only those near the scroll viewport.
struct LibraryGallery<Cards: View>: View {
  let tiles: [GalleryPlacement.Tile]
  @ViewBuilder let card: (EntityID, CGFloat) -> Cards
  @State private var width: CGFloat = 0
  @State private var placement = GalleryPlacement(width: 0, tiles: [])

  var body: some View {
    HStack(alignment: .top, spacing: GalleryPlacement.columnGap) {
      ForEach(placement.columns) { column in
        GalleryColumn(column: column, card: card)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { next in
      width = next
      placement = GalleryPlacement(width: next, tiles: tiles)
    }
    .onChange(of: tiles) { old, new in
      let next = GalleryPlacement(width: width, tiles: new)
      if old.map(\.id) == new.map(\.id) {
        placement = next
      } else {
        withAnimation(Motion.land) { placement = next }
      }
    }
  }
}

private struct GalleryColumn<Cards: View>: View {
  let column: GalleryPlacement.Column
  let card: (EntityID, CGFloat) -> Cards
  @State private var visible = 0..<0

  var body: some View {
    let cards = column.cards[visible.clamped(to: column.cards.indices)]
    VStack(alignment: .leading, spacing: GalleryPlacement.cardGap) {
      ForEach(cards) { tile in
        card(tile.id, tile.frame.width)
          .frame(width: tile.frame.width, height: tile.frame.height, alignment: .topLeading)
          .transition(.landing)
      }
    }
    .offset(y: cards.first?.frame.minY ?? 0)
    .frame(width: column.width, height: column.height, alignment: .topLeading)
    .onGeometryChange(for: Range<Int>.self) { [column] geometry in
      let bounds = geometry.bounds(of: .scrollView) ?? CGRect(origin: .zero, size: geometry.size)
      return column.visible(in: (bounds.minY - 256)...(bounds.maxY + 256))
    } action: {
      visible = $0
    }
  }
}

struct GalleryPlacement {
  struct Tile: Equatable {
    let id: EntityID
    let kind: ItemKind
    let busy: Bool
  }

  struct Placed: Identifiable, Sendable {
    let id: EntityID
    let frame: CGRect
  }

  struct Column: Identifiable, Sendable {
    let id: Int
    let cards: [Placed]
    let width: CGFloat
    let height: CGFloat

    func visible(in range: ClosedRange<CGFloat>) -> Range<Int> {
      let first = boundary { $0.frame.maxY >= range.lowerBound }
      let last = boundary { $0.frame.minY > range.upperBound }
      return first..<last
    }

    private func boundary(_ isPast: (Placed) -> Bool) -> Int {
      var start = 0
      var end = cards.count
      while start < end {
        let middle = (start + end) / 2
        if isPast(cards[middle]) { end = middle } else { start = middle + 1 }
      }
      return start
    }
  }

  static let columnGap: CGFloat = 22
  static let cardGap: CGFloat = 26
  let columns: [Column]

  @MainActor init(width: CGFloat, tiles: [Tile]) {
    let frames =
      width > 0
      ? Self.frames(width: width, count: tiles.count) { index, width in
        let tile = tiles[index]
        return GalleryCard.height(at: width, kind: tile.kind, busy: tile.busy)
      }
      : []
    let placed = zip(tiles, frames).map { tile, frame in Placed(id: tile.id, frame: frame) }
    columns = Dictionary(grouping: placed) { $0.frame.minX }
      .sorted { $0.key < $1.key }
      .enumerated().compactMap { index, column in
        guard let last = column.value.last else { return nil }
        return Column(id: index, cards: column.value, width: last.frame.width, height: last.frame.maxY)
      }
  }

  static func frames(width: CGFloat, count: Int, height: (Int, CGFloat) -> CGFloat) -> [CGRect] {
    let gap = columnGap
    let columns = max(1, Int((width + gap) / (Size.cardMinimumWidth + gap)))
    let cardWidth = min(340, (width - gap * CGFloat(columns - 1)) / CGFloat(columns))
    var bottoms = Array(repeating: CGFloat.zero, count: columns)
    return (0..<count).map { index in
      let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
      let frame = CGRect(
        x: CGFloat(column) * (cardWidth + gap), y: bottoms[column], width: cardWidth, height: height(index, cardWidth))
      bottoms[column] = frame.maxY + cardGap
      return frame
    }
  }
}

extension AnyTransition {
  /// A card dropping into the gallery from a little above, settling with a small bounce.
  static var landing: AnyTransition {
    .asymmetric(
      insertion: .modifier(active: Landing(lifted: true), identity: Landing(lifted: false)),
      removal: .opacity.combined(with: .scale(scale: 0.94)))
  }
}

private struct Landing: ViewModifier {
  let lifted: Bool

  func body(content: Content) -> some View {
    content
      .offset(y: lifted ? -34 : 0)
      .scaleEffect(lifted ? 0.9 : 1, anchor: .bottom)
      .opacity(lifted ? 0 : 1)
  }
}
