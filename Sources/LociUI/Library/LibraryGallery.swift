import LociModel
import SwiftUI

/// Every item as a card, about four to a row and more or fewer as the window widens or narrows. A click goes
/// to `click`, which opens the item or chooses it. An item that arrives while the gallery is open drops into
/// its place.
struct LibraryGallery: View {
  let items: [Item]
  let jobs: [EntityID: Job]
  let progress: Progress
  let chosen: Set<EntityID>
  let renaming: EntityID?
  let click: (EntityID) -> Void
  let actions: CardActions
  let menu: (Item) -> ItemMenu
  let renamed: (Item, String?) -> Void

  static let columns = [
    GridItem(.adaptive(minimum: Size.cardMinimumWidth, maximum: 340), spacing: 22, alignment: .top)
  ]

  var body: some View {
    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 26) {
      ForEach(items, id: \.id) { item in
        Button {
          click(item.id)
        } label: {
          GalleryCard(
            item: item, job: jobs[item.id], share: progress.share(of: item), chosen: chosen.contains(item.id),
            actions: actions, renamed: renaming == item.id ? { renamed(item, $0) } : nil)
        }
        .buttonStyle(PressStyle())
        .contextMenu { menu(item).changesData() }
        .transition(.landing)
      }
    }
    .animation(Motion.land, value: items.map(\.id))
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
