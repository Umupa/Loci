import LociModel
import SwiftUI

/// The shelf over the list, scrolled with the page around them. A click goes to `click`, which opens the item
/// or chooses it; chosen items have an amber wash.
struct LibraryList: View {
  let items: [Item]
  let jobs: [EntityID: Job]
  let progress: Progress
  let chosen: Set<EntityID>
  let renaming: EntityID?
  let click: (EntityID) -> Void
  let act: (JobLine.Fix, Item) -> Void
  let actions: ItemActions
  /// What a right click on an item acts on.
  let acted: (EntityID) -> [EntityID]
  let renamed: (Item, String?) -> Void
  @Environment(\.controlActiveState) private var active
  @State private var pointing: EntityID?

  /// The row under the pointer, in the window in front only.
  private var hovered: EntityID? { active == .key ? pointing : nil }

  /// The items as they are laid out: the shelf, then the rows.
  static func order(of items: [Item], progress: Progress) -> [Item] {
    let shelf = progress.shelf(of: items)
    return shelf + items.filter { item in !shelf.contains { $0.id == item.id } }
  }

  var body: some View {
    let shelf = progress.shelf(of: items)
    VStack(alignment: .leading, spacing: 0) {
      if !shelf.isEmpty {
        ShelfRow(
          items: shelf, jobs: jobs, progress: progress, chosen: chosen, renaming: renaming, click: click, act: act,
          menu: menu, renamed: renamed
        )
        .padding(.bottom, 26)
      }
      let rows = items.filter { item in !shelf.contains { $0.id == item.id } }
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
        let lit = chosen.contains(item.id) || hovered == item.id
        let litBefore = index > 0 && (chosen.contains(rows[index - 1].id) || hovered == rows[index - 1].id)
        Button {
          click(item.id)
        } label: {
          LibraryRow(
            item: item, job: jobs[item.id], share: progress.share(of: item), act: { act($0, item) },
            renamed: renaming == item.id ? { renamed(item, $0) } : nil
          )
          .background(
            RoundedRectangle(cornerRadius: Radius.cover, style: .continuous)
              .fill(chosen.contains(item.id) ? Palette.tint : hovered == item.id ? Palette.fill : .clear)
          )
          .overlay(alignment: .top) {
            if index > 0, !lit, !litBefore {
              Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
                .padding(.leading, Size.listThumbnail + Spacing.xs + 14)
                .padding(.trailing, Spacing.xs)
            }
          }
        }
        .buttonStyle(.plain)
        .onHover { inside in pointing = inside ? item.id : (pointing == item.id ? nil : pointing) }
        .contextMenu { menu(item).changesData() }
      }
    }
  }

  private func menu(_ item: Item) -> ItemMenu {
    var working = false
    if case .working = JobLine(jobs[item.id]) { working = true }
    return ItemMenu(item: item, acted: acted(item.id), actions: actions, working: working)
  }
}

/// Up to three large covers, the first a little wider than the others.
struct ShelfRow: View {
  let items: [Item]
  let jobs: [EntityID: Job]
  let progress: Progress
  var chosen: Set<EntityID> = []
  var renaming: EntityID?
  let click: (EntityID) -> Void
  let act: (JobLine.Fix, Item) -> Void
  let menu: (Item) -> ItemMenu
  var renamed: (Item, String?) -> Void = { _, _ in }

  var body: some View {
    GeometryReader { frame in
      let gaps = Size.shelfGap * 2
      let unit = (frame.size.width - gaps) / (Size.shelfLead + 2)
      HStack(spacing: Size.shelfGap) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          Button {
            click(item.id)
          } label: {
            ShelfCover(
              item: item, share: progress.share(of: item), job: jobs[item.id], act: { act($0, item) },
              chosen: chosen.contains(item.id), renamed: renaming == item.id ? { renamed(item, $0) } : nil)
          }
          .buttonStyle(PressStyle())
          .frame(width: index == 0 ? unit * Size.shelfLead : unit)
          .contextMenu { menu(item).changesData() }
        }
      }
    }
    .frame(height: Size.shelfHeight)
  }
}
