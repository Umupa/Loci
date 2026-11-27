import LociModel
import SwiftUI

/// The companion in the chat's top-left corner, as a chat app names who you are talking to: its face with its
/// dot, its name, and a line saying what it is doing, how tired it is, or that its Mac is offline. Choosing it
/// opens the companion's home page.
struct CompanionBadge: View {
  @Environment(\.companionName) private var name
  @Environment(\.companionNow) private var now
  @Environment(\.companionFlight) private var flight
  @Environment(\.companionHomeShown) private var homeShown
  @Environment(\.openPlace) private var openPlace
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button {
      openPlace(.loci)
    } label: {
      HStack(spacing: 9) {
        face
        VStack(alignment: .leading, spacing: 1) {
          title
          if let line = now.line {
            Text(line)
              .font(.system(size: 11.5))
              .foregroundStyle(Palette.inkMuted)
              .lineLimit(1)
              .id(line.key)
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
          }
        }
        .animation(reduceMotion ? nil : Motion.swap, value: now.line?.key)
      }
      .padding(.vertical, Spacing.xxs)
      .padding(.leading, Spacing.xxs)
      .padding(.trailing, 10)
      .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? Palette.fill : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .accessibilityLabel(nameText)
    .accessibilityValue(now.line.map { Text($0) } ?? Text(verbatim: ""))
    .accessibilityHint(Text(.loci("companion.openHome")))
  }

  @ViewBuilder private var face: some View {
    if homeShown {
      Color.clear.frame(width: Self.face, height: Self.face)
    } else {
      LociAvatar(size: Self.face)
        .flying(.face, in: flight)
        .presenceDot(now.tone, side: Self.face)
    }
  }

  @ViewBuilder private var title: some View {
    if homeShown {
      nameText.font(Self.nameFont).hidden()
    } else {
      nameText.font(Self.nameFont).foregroundStyle(Palette.ink).lineLimit(1).flying(.name, in: flight)
    }
  }

  private var nameText: Text { name.isEmpty ? Text(.loci("companion.title")) : Text(verbatim: name) }

  private static let face: CGFloat = 30
  private static let nameFont = Font.system(size: 14, weight: .semibold)

  /// Where the badge starts: clear of the window's buttons and the sidebar's button while the sidebar is hidden.
  static func leading(sidebarShown: Bool) -> CGFloat {
    sidebarShown ? Spacing.m : Size.sidebarToggleLeading + Size.iconButton + Spacing.xs
  }
}

extension CompanionNow {
  /// The line under the companion's name in the chat: what it is doing, that its Mac is offline, or how tired
  /// it is; nothing from a Mac that does not say.
  var line: LocalizedStringResource? {
    if offline { return .loci("companion.offline") }
    if let work { return work.words }
    return presence.map { FeelingLine.name($0.tiredness) }
  }

  /// The line under its name in the sidebar: what it is doing, or else the last thing it said in the chat.
  var sidebarLine: Text? {
    if let work { return Text(work.words) }
    return presence?.lastSaid.flatMap(Self.oneLine).map { Text(verbatim: $0) }
  }

  /// The last bubble of a reply as one line of plain words, as a chat list shows the latest message.
  static func oneLine(_ reply: String) -> String? {
    guard let last = BubbleLayout.bubbles(in: reply).last else { return nil }
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let plain = (try? AttributedString(markdown: last, options: options)).map { String($0.characters) } ?? last
    let words = plain.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }.joined(separator: " ")
    return words.isEmpty ? nil : words
  }
}
