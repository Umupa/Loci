import LociModel
import SwiftUI

struct LibraryScreen: View {
  let kind: ItemKind?
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  let delete: (Item) -> Void
  @State private var feed: Feed<[Item]>?

  var body: some View {
    LibraryWall(items: shown, delete: delete)
      .navigationTitle(kind.map { Text(Messages.name(of: $0)) } ?? Text(.loci("sidebar.library")))
      .acceptingTextFiles(opened: opened, failed: failed)
      .subscribing(AllItems(), into: $feed)
  }

  private var shown: [Item] {
    let items = feed?.value ?? []
    guard let kind else { return items }
    return items.filter { ItemKind($0.kind) == kind }
  }
}

/// Every item as a card, newest first, as many columns as fit.
struct LibraryWall: View {
  let items: [Item]
  let delete: (Item) -> Void

  var body: some View {
    if items.isEmpty {
      EmptyMark(symbol: Symbols.library)
    } else {
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: Size.cardMinimumWidth), spacing: Spacing.m, alignment: .top)],
          alignment: .leading, spacing: Spacing.l
        ) {
          ForEach(items, id: \.id) { item in
            NavigationLink(value: Page.item(item.id)) { ItemCard(item: item) }
              .buttonStyle(.plain)
              .contextMenu {
                Button(role: .destructive) {
                  delete(item)
                } label: {
                  Text(.loci("item.delete"))
                }
              }
          }
        }
        .padding(Spacing.l)
      }
      .background(Palette.canvas)
    }
  }
}

struct ItemCard: View {
  let item: Item

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      RoundedRectangle(cornerRadius: Radius.card)
        .fill(Palette.surface)
        .aspectRatio(Size.cardThumbnailRatio, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.line, lineWidth: Size.hairline))
        .overlay {
          Image(systemName: Symbols.kind(ItemKind(item.kind)))
            .font(.system(size: Size.thumbnailSymbol, weight: .light))
            .foregroundStyle(Palette.inkMuted)
        }
      HStack(spacing: Spacing.xxs) {
        Tag(text: Text(Messages.name(of: ItemKind(item.kind))))
        if let language = item.language { Tag(text: Text(verbatim: language)) }
      }
      Text(verbatim: item.title)
        .font(Typography.bodyEmphasis)
        .foregroundStyle(Palette.ink)
        .lineLimit(2)
    }
    .contentShape(Rectangle())
  }
}
