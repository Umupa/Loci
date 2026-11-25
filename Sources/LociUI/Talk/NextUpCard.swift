import LociModel
import SwiftUI

/// A card with a question: where it comes from, what happened, and the amber button that starts it. Keep,
/// later and decline show under the pointer.
struct NextUpCard: View {
  let card: NextUp
  let question: String
  let project: Project?
  let actions: NextUpActions
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var pointed = false

  var body: some View {
    NextUpFace {
      HStack(alignment: .bottom, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          NextUpSource(project: project)
          Text(verbatim: card.what)
            .font(.system(size: 14))
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        start
      }
      .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 14))
      .overlay(alignment: .topTrailing) {
        if changesAllowed { choices.opacity(pointed ? 1 : 0).padding(.top, 8).padding(.trailing, 10) }
      }
    }
    .help(Text(verbatim: question))
    .onHover { hovering in withAnimation(reduceMotion ? nil : Motion.quick) { pointed = hovering } }
    .anchorPreference(key: NextUpAnchors.self, value: .bounds) { NextUpAnchors.Value(cards: [card.id: $0]) }
  }

  private var start: some View {
    Button {
      actions.start(card)
    } label: {
      Image(systemName: "arrow.right")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Palette.onAccent)
        .frame(width: 34, height: 34)
        .background(Circle().fill(Palette.accent))
        .shadow(color: Palette.accentLine, radius: 7, y: 4)
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .help(Text(.loci("deck.start")))
    .accessibilityLabel(Text(.loci("deck.start")))
    .disabled(!changesAllowed)
  }

  private var choices: some View {
    HStack(spacing: 0) {
      let kept = card.state == .kept
      choice(kept ? "pin.fill" : "pin", .loci("deck.keep"), tint: kept ? Palette.accentInk : nil) {
        actions.set(card, kept ? .restore : .keep)
      }
      Menu {
        Button(.loci("deck.inAnHour")) { actions.set(card, .later(.after(minutes: 60))) }
        Button(.loci("deck.tonight")) { putOff(until: 20) }
        Button(.loci("deck.tomorrow")) { putOff(until: 9) }
      } label: {
        NextUpChoiceFace(symbol: "clock", tint: nil)
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .help(Text(.loci("deck.later")))
      choice("xmark", .loci("deck.decline"), tint: nil) { actions.set(card, .decline) }
    }
  }

  /// Puts the card off until the clock next shows the hour.
  private func putOff(until hour: Int) {
    guard let time = TimeOfDay(hour: hour, minute: 0) else { return }
    actions.set(card, .later(.next(time)))
  }

  private func choice(
    _ symbol: String, _ title: LocalizedStringResource, tint: Color?, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) { NextUpChoiceFace(symbol: symbol, tint: tint) }
      .buttonStyle(.plain)
      .help(Text(title))
      .accessibilityLabel(Text(title))
  }
}

/// A small round button on a card, washed under the pointer.
struct NextUpChoiceFace: View {
  let symbol: String
  let tint: Color?
  @State private var pointed = false

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 11.5, weight: .semibold))
      .foregroundStyle(tint ?? (pointed ? Palette.ink : Palette.inkMuted))
      .frame(width: 26, height: 24)
      .background(Capsule(style: .circular).fill(pointed ? Palette.fill : .clear))
      .contentShape(Capsule(style: .circular))
      .onHover { pointed = $0 }
  }
}
