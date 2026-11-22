import LociModel
import SwiftUI

/// The foot of the sidebar once this Mac is paired with another: the shown Mac's name, quiet until the pointer
/// is on it. A dot follows the name while a remote Mac is out of reach.
struct MachineFoot: View {
  @Environment(\.machineChoice) private var choice
  @Environment(\.standIns) private var standIns
  @State private var hovering = false

  var body: some View {
    if let choice, !choice.roster.paired.isEmpty {
      let lit = hovering || choice.menuOpen || standIns?.pointerOnMachineFoot == true
      Button(action: choice.openMenu) {
        HStack(spacing: 10) {
          Image(systemName: Symbols.machine(choice.shown.model))
            .font(.system(size: 14))
            .foregroundStyle(Palette.inkFaint)
            .frame(width: 17, height: 17)
          HStack(spacing: 7) {
            Text(verbatim: choice.shown.name).lineLimit(1)
            if let link = choice.link, link != .connected { LinkDot(link: link) }
          }
          Spacer(minLength: 0)
          Image(systemName: Symbols.popup)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.inkFaint)
            .frame(width: Spacing.m)
            .opacity(lit ? 1 : 0)
        }
        .font(.system(size: 13.5))
        .foregroundStyle(Palette.sidebarInkMuted)
        .padding(.vertical, 6)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .background(
          RoundedRectangle(cornerRadius: Radius.sidebarRow, style: .continuous).fill(lit ? Palette.fill : .clear)
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
      .onHover { hovering = $0 }
      .padding(.horizontal, 10)
      .padding(.top, Spacing.xxs)
      .padding(.bottom, Spacing.xs)
      .accessibilityLabel(Text(verbatim: choice.shown.name))
    }
  }
}

/// Amber and pulsing while a Mac is dialed again, gray while it is offline.
struct LinkDot: View {
  @Environment(\.reducesMotion) private var reduceMotion
  let link: LociModel.Link
  @State private var pulsing = false

  var body: some View {
    Circle()
      .fill(link == .reconnecting ? Palette.accent : Palette.inkFaint)
      .frame(width: Size.dot, height: Size.dot)
      .background {
        if link == .reconnecting {
          Circle()
            .stroke(Palette.accent.opacity(pulsing ? 0 : 0.6), lineWidth: 1)
            .scaleEffect(pulsing ? 2.6 : 1)
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulsing)
            .onAppear { pulsing = !reduceMotion }
        }
      }
  }
}
