import LociModel
import SwiftUI

enum LibraryPresentation: String, CaseIterable {
  case gallery, list

  static let key = "libraryPresentation"

  var name: LocalizedStringResource {
    switch self {
    case .gallery: .loci("library.gallery")
    case .list: .loci("library.list")
    }
  }

  var symbol: String {
    switch self {
    case .gallery: "square.grid.2x2"
    case .list: "list.bullet"
    }
  }
}

struct LibraryEntries: View {
  let items: [Item]
  let jobs: [EntityID: Job]
  let progress: Progress
  let chosen: Set<EntityID>
  let renaming: EntityID?
  let click: (EntityID) -> Void
  let actions: CardActions
  let menu: (Item) -> ItemMenu
  let renamed: (Item, String?) -> Void
  var presentation: LibraryPresentation = .gallery

  var body: some View {
    switch presentation {
    case .gallery:
      let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      LibraryGallery(
        tiles: items.map {
          GalleryPlacement.Tile(id: $0.id, kind: ItemKind($0.kind), busy: CardState(jobs[$0.id]).isBusy)
        }
      ) { id, width in
        if let item = byID[id] {
          entry(item) { selected, editing in
            GalleryCard(
              item: item, job: jobs[id], share: progress.share(of: item), chosen: selected, actions: actions,
              coverWidth: width, renamed: editing)
          }
        }
      }
    case .list:
      LibraryList {
        ForEach(items, id: \.id) { item in
          entry(item) { selected, editing in
            LibraryRow(item: item, reading: progress.states[item.id], chosen: selected, renamed: editing)
          }
        }
      }
    }
  }

  private func entry<Label: View>(
    _ item: Item, @ViewBuilder label: (Bool, ((String?) -> Void)?) -> Label
  ) -> some View {
    let selected = chosen.contains(item.id)
    let editing: ((String?) -> Void)? = renaming == item.id ? { renamed(item, $0) } : nil
    return Button {
      click(item.id)
    } label: {
      label(selected, editing)
    }
    .buttonStyle(PressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .contextMenu { menu(item).changesData() }
  }
}
