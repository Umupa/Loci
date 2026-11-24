import AppKit
import SwiftUI

/// The pictures a highlight covers, as small rounded pictures behind an amber bar; a click opens one large.
struct NotePictures: View {
  let addresses: [String]
  let images: [String: NSImage]
  @State private var opened: OpenedPicture?

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      RoundedRectangle(cornerRadius: 1).fill(Palette.accent.opacity(0.8)).frame(width: 2)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        ForEach(addresses, id: \.self) { address in
          if let image = images[address] {
            Button {
              opened = OpenedPicture(image: image)
            } label: {
              thumbnail(image)
            }
            .buttonStyle(PressStyle())
            .help(Text(.loci("picture.open")))
            .accessibilityLabel(Text(.loci("picture.open")))
          } else {
            missing
          }
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .sheet(item: $opened) { PictureSheet(image: $0.image) }
  }

  private func thumbnail(_ image: NSImage) -> some View {
    Image(nsImage: image)
      .resizable()
      .scaledToFit()
      .frame(maxWidth: .infinity, maxHeight: Size.notePicture)
      .padding(Spacing.xs)
      .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.surface))
      .clipShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(
          Palette.lineStrong, lineWidth: Size.hairline)
      )
      .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
  }

  private var missing: some View {
    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
      .fill(Palette.fill)
      .frame(height: 64)
      .overlay { Image(systemName: Symbols.picture).font(.system(size: 18)).foregroundStyle(Palette.inkFaint) }
  }
}

/// A picture opened from a highlight.
private struct OpenedPicture: Identifiable {
  let id = UUID()
  let image: NSImage
}

/// A picture as large as the window allows; a click or Escape puts it away.
private struct PictureSheet: View {
  @Environment(\.dismiss) private var dismiss
  let image: NSImage

  var body: some View {
    Image(nsImage: image)
      .resizable()
      .scaledToFit()
      .frame(maxWidth: min(image.size.width, Size.openedPicture), maxHeight: min(image.size.height, Size.openedPicture))
      .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
      .padding(Spacing.l)
      .background(Palette.canvas)
      .contentShape(Rectangle())
      .onTapGesture { dismiss() }
      .onExitCommand { dismiss() }
  }
}
