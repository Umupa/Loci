import AppKit
import LociModel
import SwiftUI

/// What can be done to items in the library from their menu.
struct ItemActions {
  let rename: (Item) -> Void
  let changeCover: (Item) -> Void
  let delete: ([EntityID]) -> Void
  var freeSpace: (Item) -> Void = { _ in }
  var saveLocally: (Item) -> Void = { _ in }
}

/// The menu on a card. On one of several chosen items it only deletes them all.
struct ItemMenu: View {
  let item: Item
  let acted: [EntityID]
  let actions: ItemActions
  /// The item's media on the host, for a video or episode from a link with no work going on.
  var space: ItemSpace?

  var body: some View {
    if acted.count > 1 {
      Button(role: .destructive) {
        actions.delete(acted)
      } label: {
        Text(.loci("item.deleteSome \(acted.count)"))
      }
    } else {
      Button {
        actions.rename(item)
      } label: {
        Text(.loci("item.rename"))
      }
      Button {
        actions.changeCover(item)
      } label: {
        Text(.loci("item.changeCover"))
      }
      if let space, space.fromLink {
        if let bytes = space.bytes {
          let size = Bytes.text(bytes)
          Button {
            actions.freeSpace(item)
          } label: {
            Text(.loci("item.freeSpace \(size)"))
          }
        } else {
          Button {
            actions.saveLocally(item)
          } label: {
            Text(.loci("item.saveLocally"))
          }
        }
      }
      if let source = item.source {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(source.absoluteString, forType: .string)
        } label: {
          Text(.loci("item.copyLink"))
        }
      }
      Divider()
      Button(role: .destructive) {
        actions.delete([item.id])
      } label: {
        Text(.loci("item.delete"))
      }
    }
  }
}

/// The title being renamed in place. Return keeps it; Escape, clicking elsewhere or leaving it empty puts the
/// old one back.
struct TitleField: View {
  let title: String
  let font: Font
  let ink: Color
  let done: (String?) -> Void
  @State private var text: String
  @FocusState private var focused: Bool

  init(title: String, font: Font, ink: Color, done: @escaping (String?) -> Void) {
    self.title = title
    self.font = font
    self.ink = ink
    self.done = done
    _text = State(initialValue: title)
  }

  var body: some View {
    TextField(text: $text) { Text(verbatim: title) }
      .textFieldStyle(.plain)
      .font(font)
      .foregroundStyle(ink)
      .focused($focused)
      .onSubmit { done(Self.kept(text, over: title)) }
      .onExitCommand { done(nil) }
      .onChange(of: focused) { if !focused { done(nil) } }
      .onAppear { focused = true }
  }

  /// The new title to keep, or `nil` when there is nothing new.
  static func kept(_ text: String, over title: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed == title ? nil : trimmed
  }
}

/// At the foot of the library after a deletion: how many went, and the button that brings them back.
struct DeletedNotice: View {
  let count: Int
  let undo: () -> Void

  var body: some View {
    HStack(spacing: Spacing.s) {
      Text(.loci("library.deleted \(count)"))
        .font(Typography.control)
        .foregroundStyle(Palette.ink)
      Button(action: undo) {
        Text(.loci("library.undo"))
          .font(Typography.control.weight(.semibold))
          .foregroundStyle(Palette.accentInk)
          .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
    }
    .padding(.horizontal, Spacing.m)
    .frame(height: 36)
    .glassEffect(.regular, in: .capsule)
    .overlay(Capsule().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .shadow(color: .black.opacity(0.10), radius: 12, y: 8)
  }
}
