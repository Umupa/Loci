import LociModel
import SwiftUI

/// An item in the library as a card in the conversation, the same as a link's: its cover, or for an
/// article Loci wrote a page of paper with its title, then its title and a line under it.
struct LibraryCard: View {
  let item: Item
  let line: Text
  var showsWords = true
  /// How far along its work is, from 0 to 1, drawn along the foot of the cover while it goes on.
  var progress: Double?

  var body: some View {
    CardShell(title: Text(verbatim: item.title), source: line, showsWords: showsWords) {
      picture.overlay(alignment: .bottom) {
        if let progress { ProgressLine(share: progress) }
      }
    }
  }

  @ViewBuilder private var picture: some View {
    if LociAuthor.wrote(item) {
      PaperPage(title: item.title)
    } else {
      Cover(item: item, corner: 0, symbolSize: 18, backdrop: Palette.cardInset)
    }
  }
}

/// The page an article Loci wrote shows on its card: its title in the serif on paper, over a few lines.
private struct PaperPage: View {
  let title: String

  var body: some View {
    GeometryReader { page in
      VStack(alignment: .leading, spacing: 8) {
        Text(Serif.attributed(title, Serif.Face(size: 19, weight: .semibold)))
          .foregroundStyle(Palette.cardPageInk)
          .lineLimit(2)
          .padding(.bottom, 4)
        ForEach([0.92, 0.8, 0.86, 0.58], id: \.self) { share in
          Capsule().fill(Palette.cardPageInk.opacity(0.12)).frame(width: (page.size.width - 40) * share, height: 5)
        }
      }
      .padding(.vertical, 16)
      .padding(.horizontal, 20)
      .frame(width: page.size.width, height: page.size.height, alignment: .topLeading)
    }
    .background(Palette.cardPage)
  }
}

/// Items one after another in the library, as one card or a stack of them; each opens its item.
struct LibraryCards: View {
  @Environment(\.openPage) private var openPage
  let items: [Item]
  let line: (Item) -> Text

  var body: some View {
    CardStack(cards: items) { item, showsWords in
      LibraryCard(item: item, line: line(item), showsWords: showsWords)
    } open: { item in
      openPage(.item(item.id))
    }
  }
}
