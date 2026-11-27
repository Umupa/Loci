import LociModel
import SwiftUI

/// The top of the companion's home page, left to right: its face with its dot; its name, which the person can
/// change; how it is; what you have done together; and, at the far end, a button to message it.
struct HomeHeader: View {
  let page: LociPage?
  let message: (() -> Void)?
  /// Whether the parts under the face rise in after it.
  let rise: Bool
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @Environment(\.companionName) private var name
  @Environment(\.companionNow) private var now
  @Environment(\.companionFlight) private var flight
  @State private var renaming = false
  @State private var draft = ""
  @State private var risen = false

  var body: some View {
    HStack(alignment: .top, spacing: 26) {
      Portrait()
      VStack(alignment: .leading, spacing: 9) {
        nameButton
        status.rising(1, risen: risen, when: rise)
        if let together = page?.together {
          FlowRow(spacing: Spacing.xs) {
            FactPill(count: together.days, unit: .loci("loci.days"))
            FactPill(count: together.messages, unit: .loci("loci.messages"))
            FactPill(count: together.itemsReadTogether, unit: .loci("loci.readTogether"))
          }
          .rising(2, risen: risen, when: rise)
        }
      }
      .padding(.top, Spacing.xxs)
      Spacer(minLength: Spacing.m)
      if let message {
        Button(action: message) {
          Label {
            Text(.loci("companion.message"))
          } icon: {
            Image(systemName: Symbols.ask)
          }
        }
        .buttonStyle(AmberButtonStyle())
        .padding(.top, Spacing.s)
        .rising(1, risen: risen, when: rise)
      }
    }
    .onAppear { risen = true }
    .alert(Text(.loci("companion.name")), isPresented: $renaming) {
      TextField(text: $draft) { Text(.loci("companion.name")) }
      Button(.loci("dialog.cancel"), role: .cancel) {}
      Button(.loci("loci.save")) { rename(draft) }
    }
  }

  private var nameButton: some View {
    Button {
      draft = name
      renaming = true
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
        (name.isEmpty ? Text(.loci("companion.title")) : Text(verbatim: name))
          .font(.system(size: 34, weight: .semibold, design: .serif))
          .foregroundStyle(Palette.ink)
          .lineLimit(1)
          .flying(.name, in: flight)
        Image(systemName: Symbols.pencil).font(.system(size: 13)).foregroundStyle(Palette.inkFaint)
      }
    }
    .buttonStyle(.plain)
    .help(Text(.loci("companion.name")))
    .changesData()
  }

  /// Its dot, that its Mac is offline when it is, then its mood, how good it feels, its energy and how tired it is.
  private var status: some View {
    HStack(spacing: Spacing.s) {
      HStack(spacing: 5) {
        Circle().fill(now.tone.color).frame(width: 7, height: 7)
        if now.offline {
          Text(.loci("companion.offline")).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted)
        }
      }
      if let feeling = page?.feeling {
        FeelingLine(feeling: feeling)
      }
    }
  }

  private func rename(_ name: String) {
    Task {
      do throws(HostError) {
        _ = try await host.run(RenameCompanion(name))
      } catch {
        showFailure(error)
      }
    }
  }
}

/// A count and what it counts, in a quiet capsule.
private struct FactPill: View {
  let count: Int
  let unit: LocalizedStringResource

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      Text(count, format: .number).font(.system(size: 12, weight: .medium).monospaced()).foregroundStyle(Palette.ink)
      Text(unit).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
    }
    .padding(.vertical, 3)
    .padding(.horizontal, 9)
    .background(Palette.fill, in: Capsule())
    .fixedSize()
  }
}
