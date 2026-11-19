import LociModel
import SwiftUI

/// The Macs paired with this one, to remove, and adding another. With none paired, only the way to add one.
struct RemoteSettingsPage: View {
  @Environment(\.machineChoice) private var choice

  var body: some View {
    SettingsPage(symbol: Symbols.remote, title: .loci("settings.remote"), width: Size.wideSettingsWidth) {
      if let choice, !choice.roster.paired.isEmpty {
        VStack(alignment: .trailing, spacing: 6) {
          SettingsGroup(title: nil, inset: 50) {
            ForEach(Array(choice.roster.paired.enumerated()), id: \.element.id) { index, paired in
              PairedMacRow(paired: paired, first: index == 0) { choice.remove(paired.id) }
            }
          }
          addButton.padding(.horizontal, 6).padding(.top, 2)
        }
      } else {
        VStack(spacing: 22) {
          Image(systemName: Symbols.machine(.laptop))
            .font(.system(size: 80, weight: .ultraLight))
            .foregroundStyle(Palette.inkFaint.opacity(0.7))
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
          addButton
        }
        .frame(maxWidth: .infinity, minHeight: 560)
        .padding(.bottom, 120)
      }
    }
  }

  private var addButton: some View {
    Button {
      choice?.addMac()
    } label: {
      Text(.loci("remote.addMac"))
    }
    .buttonStyle(PushStyle())
  }
}

private struct PairedMacRow: View {
  @Environment(\.standIns) private var standIns
  let paired: PairedMachine
  let first: Bool
  let remove: () -> Void
  @State private var hovering = false

  var body: some View {
    SettingsRow {
      HStack(spacing: 10) {
        Image(systemName: Symbols.machine(paired.machine.model))
          .font(.system(size: 14))
          .foregroundStyle(.white)
          .frame(width: Size.componentTile, height: Size.componentTile)
          .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(
              LinearGradient(
                colors: [Color(nsColor: NSColor(rgb: 0x8A919B)), Color(nsColor: NSColor(rgb: 0x5C636D))],
                startPoint: .top, endPoint: .bottom))
          )
        Text(verbatim: paired.machine.name).lineLimit(1)
      }
      .opacity(paired.link == .offline ? 0.42 : 1)
    } trailing: {
      Button(action: remove) {
        Text(.loci("remote.remove"))
      }
      .buttonStyle(PushStyle())
      .opacity(hovering || (first && standIns?.pointerOnFirstPairedMac == true) ? 1 : 0)
    }
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
  }
}
