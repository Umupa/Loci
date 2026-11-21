import SwiftUI

extension Palette {
  /// A card in the conversation: a link, or an item in the library.
  static let card = Color(dark: 0x2A2723, light: 0xFFFFFF)
  /// Inside a card, where its picture goes before it arrives.
  static let cardInset = Color(dark: 0x34302B, light: 0xF6F4EF)
  /// The page an article Loci wrote shows on its card, paper in light and dark alike.
  static let cardPage = Color(dark: 0xF4F1EA, light: 0xF6F3EC)
  static let cardPageInk = Color(nsColor: NSColor(rgb: 0x1D1D1F))
}

/// The one look of every card in the conversation: a picture inset in a rounded card, a title under it,
/// and a line of where it comes from. Without a picture, only the words.
struct CardShell<Picture: View>: View {
  let title: Text
  let source: Text?
  /// Whether the words show; a card at the back of a stack hides them.
  var showsWords = true
  /// `nil` for a card with only its words.
  let picture: Picture?

  init(title: Text, source: Text?, showsWords: Bool = true, picture: Picture?) {
    self.title = title
    self.source = source
    self.showsWords = showsWords
    self.picture = picture
  }

  static var width: CGFloat { 262 }
  static var corner: CGFloat { 26 }
  static var pictureCorner: CGFloat { 20 }
  static var inset: CGFloat { 7 }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      if let picture {
        Color.clear
          .aspectRatio(2, contentMode: .fit)
          .overlay { picture }
          .background(Palette.cardInset)
          .clipShape(RoundedRectangle(cornerRadius: Self.pictureCorner, style: .continuous))
      }
      VStack(alignment: .leading, spacing: 3) {
        title.font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
        source?.font(.system(size: 14)).foregroundStyle(Palette.inkMuted)
      }
      .lineLimit(1)
      .truncationMode(.tail)
      .padding(.horizontal, 10)
      .padding(.top, picture == nil ? 9 : 12)
      .opacity(showsWords ? 1 : 0)
    }
    .padding([.horizontal, .top], Self.inset)
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.card, in: shape)
    .contentShape(shape)
    .modifier(CardLift(shape: shape))
  }
}

/// A hairline around a card and a soft shadow under it, deeper in dark.
private struct CardLift<S: InsettableShape>: ViewModifier {
  let shape: S
  @Environment(\.colorScheme) private var scheme

  func body(content: Content) -> some View {
    content
      .overlay(shape.strokeBorder(Palette.line, lineWidth: Size.hairline))
      .shadow(
        color: (scheme == .dark ? Color.black : Palette.warmShadow).opacity(scheme == .dark ? 0.18 : 0.10),
        radius: 14, y: 10)
  }
}

extension CardShell where Picture == EmptyView {
  init(title: Text, source: Text?, showsWords: Bool = true) {
    self.init(title: title, source: source, showsWords: showsWords, picture: nil)
  }
}
