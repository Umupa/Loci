import SwiftUI

/// A document Loci wrote, as a card in the conversation: its title in the serif, and the start of it in a
/// well that fades out. Clicking it opens the whole document over the conversation.
struct DocumentCard: View {
  @Environment(\.documents) private var documents
  /// Names the card, so the document opens from where it is and closes back into it.
  let id: AnyHashable
  let document: LociDocument

  static let width: CGFloat = 424
  static let corner: CGFloat = 24

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
    let open = documents?.shown == id
    let hidden = documents?.hidden == id
    Button {
      documents?.open(id, document)
    } label: {
      VStack(alignment: .leading, spacing: 12) {
        if let title = document.title {
          Text(Serif.attributed(title, Serif.Face(size: 22, weight: .semibold)))
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        preview
      }
      .padding([.horizontal, .top], 16)
      .padding(.bottom, 8)
      .frame(width: Self.width, alignment: .leading)
      .background(Palette.bubble, in: shape)
      .overlay(shape.strokeBorder(Palette.bubbleEdge, lineWidth: Size.hairline))
      .contentShape(shape)
    }
    .buttonStyle(PressStyle())
    .opacity(hidden ? 0 : 1)
    .background {
      if !open, let documents { shape.fill(.clear).matchedGeometryEffect(id: id, in: documents.space) }
    }
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var preview: some View {
    RichText(markdown: document.body, font: .system(size: 12))
      .environment(\.showsCopyButtons, false)
      .padding([.horizontal, .top], 12)
      .frame(height: 118, alignment: .top)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .clipped()
      .allowsHitTesting(false)
      .background(Palette.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .mask {
        LinearGradient(
          stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top,
          endPoint: .bottom)
      }
  }
}
