import LociModel
import SwiftUI

struct LibraryList<Rows: View>: View {
  @ViewBuilder let rows: Rows

  var body: some View {
    VStack(spacing: 0) {
      LibraryColumns {
        Color.clear
        Text(.loci("library.title"))
        Text(.loci("library.source"))
        Text(.loci("library.kind"))
        Text(.loci("library.added"))
        Text(.loci("library.position"))
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(Palette.inkMuted)
      .lineLimit(1)
      .frame(height: 28)
      .padding(.horizontal, 8)
      Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
      LazyVStack(spacing: 0) { rows }
    }
  }
}

struct LibraryRow: View {
  let item: Item
  let reading: ReadingState?
  let chosen: Bool
  let renamed: ((String?) -> Void)?
  @State private var hovering = false

  var body: some View {
    LibraryColumns {
      Cover(item: item, corner: Radius.thumbnail, squareInset: nil, edge: 40)
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
      title
      Group {
        if let source = item.sourceName {
          Text(verbatim: source)
        } else {
          Text(.loci("link.files"))
        }
        Text(Messages.name(of: ItemKind(item.kind)))
        Text(item.id.createdAt, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
          .monospacedDigit()
          .help(Text(item.id.createdAt, format: .dateTime.year().month().day().hour().minute()))
        Self.readingPosition(reading)
      }
      .font(.system(size: 12))
      .foregroundStyle(Palette.inkMuted)
    }
    .lineLimit(1)
    .frame(height: 54)
    .padding(.horizontal, 8)
    .background {
      RoundedRectangle(cornerRadius: Radius.row).fill(chosen ? Palette.tint : hovering ? Palette.fill : .clear)
    }
    .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
  }

  @ViewBuilder private var title: some View {
    let font = Font.system(size: 13.5, weight: .medium)
    if let renamed {
      TitleField(title: item.title, font: font, ink: Palette.ink, done: renamed)
    } else {
      Text(verbatim: item.title).font(font).foregroundStyle(Palette.ink)
    }
  }

  static func readingPosition(_ reading: ReadingState?) -> Text {
    if reading?.finished == true { return Text(.loci("talk.finished")) }
    guard case .item(_, let anchor)? = reading?.position else { return Text(verbatim: "—") }
    switch anchor {
    case .time(let span): return Text(verbatim: MediaTime.text(span.start))
    case .quote(let quote): return Text(verbatim: quote.text)
    case .page(let region): return Text(.loci("library.page \(region.page)"))
    case .lines(let code):
      let file = code.path.split(separator: "/").last ?? Substring(code.path)
      return Text(verbatim: "\(file):\(code.lines.lowerBound)")
    }
  }
}

private struct LibraryColumns: Layout {
  private let gap: CGFloat = 12

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    CGSize(width: proposal.width ?? 640, height: proposal.height ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    for (view, width) in zip(subviews, widths(in: bounds.width)) {
      view.place(
        at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: nil))
      x += width + gap
    }
  }

  private func widths(in width: CGFloat) -> [CGFloat] {
    let room = max(0, width - 40 - 56 - 92 - gap * 5)
    return [40, room * 0.54, room * 0.23, 56, 92, room * 0.23]
  }
}
