import SwiftUI

extension View {
  /// In the main conversation and a project's, sets Loci's rows off by its face: beside the first row of each
  /// reply, and room for it beside the rest, so they line up. The conversations beside something read have no
  /// face.
  @ViewBuilder func besideFace(of row: TalkRow, shown: Bool) -> some View {
    if shown, row.isLoci {
      HStack(alignment: .top, spacing: ReplyFace.gap) {
        if row.leads {
          ReplyFace()
        } else {
          Color.clear.frame(width: ReplyFace.side, height: 1).accessibilityHidden(true)
        }
        self
      }
    } else {
      self
    }
  }
}

/// Loci's face beside the first part of a reply, which opens its home page.
struct ReplyFace: View {
  @Environment(\.openPlace) private var openPlace
  @Environment(\.companionName) private var name

  var body: some View {
    Button {
      openPlace(.loci)
    } label: {
      LociAvatar(size: Self.side).contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .padding(.top, Self.lift)
    .accessibilityLabel(name.isEmpty ? Text(.loci("companion.title")) : Text(verbatim: name))
    .accessibilityHint(Text(.loci("companion.openHome")))
  }

  static let side: CGFloat = 28
  static let gap: CGFloat = 8
  /// Down from the top of the row, so the face sits level with a one-line bubble.
  private static let lift: CGFloat = 10
}
