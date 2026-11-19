import LociModel
import SwiftUI

/// One item Loci put into the library: its cover, title and byline, or its work while that goes on. The row
/// opens the item; while the pointer is on it, it offers to take the item back out.
struct SavedItemRow: View {
  @Environment(\.openPage) private var openPage
  @Environment(\.host) private var host
  let item: Item
  let work: JobLine
  /// A line above the row, from where the words begin, between it and the one before.
  var divided = false
  @State private var hovering = false

  var body: some View {
    HStack(spacing: Spacing.s) {
      Button {
        openPage(.item(item.id))
      } label: {
        HStack(spacing: Spacing.s) {
          thumbnail
          VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: item.title)
              .font(.system(size: 12.5, weight: .medium))
              .foregroundStyle(Palette.ink)
              .lineLimit(1)
              .truncationMode(.tail)
            status.font(.system(size: 11)).lineLimit(1)
          }
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Button {
        Task { _ = try? await host.run(DeleteItem(item: item.id, notes: .delete)) }
      } label: {
        Text(.loci("added.undo")).font(.system(size: 11.5)).foregroundStyle(Palette.inkMuted)
      }
      .buttonStyle(.plain)
      .opacity(hovering ? 1 : 0)
      .changesData()
    }
    .padding(.leading, Self.inset)
    .padding(.trailing, Spacing.s)
    .padding(.vertical, Spacing.xs)
    .background(hovering ? Palette.tint : Color.clear)
    .overlay(alignment: .top) {
      if divided {
        Rectangle().fill(Palette.line).frame(height: Size.hairline)
          .padding(.leading, Self.inset + Self.thumbnailSize.width + Spacing.s)
      }
    }
    .onHover { hovering = $0 }
  }

  private static let inset: CGFloat = 10
  private static let thumbnailSize = CGSize(width: 54, height: 36)

  @ViewBuilder private var thumbnail: some View {
    Group {
      if LociAuthor.wrote(item) {
        Palette.coverPlaceholder.overlay { LociAvatar(size: 22) }
      } else {
        Cover(item: item, corner: 0, symbolSize: 14, backdrop: Palette.coverPlaceholder)
      }
    }
    .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
    .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
  }

  @ViewBuilder private var status: some View {
    switch work {
    case .working(let activity, let progress):
      let said = Text(activity.name)
      if let progress {
        Shimmer(
          text: Text(
            joining: said, Text(verbatim: " "),
            Text(progress.value, format: .percent.precision(.fractionLength(0))).monospacedDigit()))
      } else {
        Shimmer(text: said)
      }
    case .action(let fix, let problem):
      HStack(spacing: 5) {
        Image(systemName: Symbols.problem).font(.system(size: 10))
        fix.why(problem) ?? Text(.loci("conversation.stopped"))
      }
      .foregroundStyle(Palette.accentInk)
    case .none:
      SavedItemByline(item).text.foregroundStyle(Palette.inkFaint)
    }
  }
}

/// An item Loci put into the library and that has been deleted since, said faintly.
struct DeletedItemLine: View {
  let title: String?

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: Symbols.tool(.delete)).font(.system(size: 10))
      if let title {
        Text(joining: Text(.loci("added.deleted")), Text(verbatim: " · "), Text(verbatim: title).strikethrough())
      } else {
        Text(.loci("added.deleted"))
      }
    }
    .font(.system(size: 11))
    .foregroundStyle(Palette.inkFaint)
    .lineLimit(1)
    .truncationMode(.tail)
    .padding(.leading, Spacing.xxs)
  }
}
