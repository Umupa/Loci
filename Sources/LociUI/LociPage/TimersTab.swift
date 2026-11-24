import LociModel
import SwiftUI

/// The companion's timers: the schedules it keeps, panels' refreshes among them, beside the follow-ups it
/// promised (WK-S2, WK-S6).
struct TimersTab: View {
  /// The schedule shown open with its runs, as when it was clicked.
  var opened: ScheduleRef?
  @State private var timers: Feed<Timers>?
  @State private var column: Feed<PanelColumn>?

  var body: some View {
    PageColumns {
      VStack(alignment: .leading, spacing: 6) {
        PageLabel(title: Text(.loci("timers.schedules")))
        if let schedules = timers?.value?.schedules {
          if schedules.isEmpty {
            EmptyTimers(symbol: Symbols.schedule, height: 118)
          } else {
            TimerCard {
              ForEach(Array(schedules.enumerated()), id: \.element.id) { index, entry in
                ScheduleRow(entry: entry, panels: panels, open: entry.ref == opened).rule(index > 0)
              }
            }
          }
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        PageLabel(title: Text(.loci("timers.followUps")))
        if let followUps = timers?.value?.followUps {
          if followUps.isEmpty {
            EmptyTimers(symbol: Symbols.followUp, height: 84)
          } else {
            TimerCard {
              ForEach(Array(followUps.enumerated()), id: \.element.id) { index, followUp in
                FollowUpRow(followUp: followUp).rule(index > 0)
              }
            }
          }
        }
      }
    }
    .subscribing(WatchTimers(), into: $timers)
    .subscribing(WatchPanelColumn(), into: $column)
  }

  private var panels: [String: String] {
    var titles: [String: String] = [:]
    for case .panel(let panel) in column?.value?.slots ?? [] { titles[panel.name] = panel.title }
    return titles
  }
}

/// Rows on one card, as the memory page draws its lists.
struct TimerCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
    VStack(alignment: .leading, spacing: 0) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.surface)
      .clipShape(shape)
      .cardShadow(shape)
  }
}

extension View {
  /// A hairline over a row that follows another.
  func rule(_ shown: Bool) -> some View {
    overlay(alignment: .top) {
      if shown { Rectangle().fill(Palette.line).frame(height: Size.hairline).padding(.leading, 14) }
    }
  }
}

/// Where timers would be: a dashed outline round a faint symbol, and no words.
private struct EmptyTimers: View {
  let symbol: String
  let height: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
      .strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      .frame(height: height)
      .overlay {
        Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Palette.inkFaint)
      }
      .accessibilityHidden(true)
  }
}

/// A promise the companion made to look again: when, what, and cancelling it.
private struct FollowUpRow: View {
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @Environment(\.fixedNow) private var fixedNow
  let followUp: FollowUp
  @State private var hovering = false
  @State private var cancelled = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
      TimerTime.label(followUp.due.date, now: fixedNow ?? Date())
        .font(.system(size: 12).monospaced())
        .foregroundStyle(Palette.inkMuted)
        .frame(width: 96, alignment: .leading)
      Text(verbatim: followUp.what)
        .font(.system(size: 13))
        .lineSpacing(3)
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.trailing, 26)
    .overlay(alignment: .trailing) { cancel.opacity(hovering ? 1 : 0) }
    .padding(.vertical, 11)
    .padding(.horizontal, 14)
    .background(hovering ? Palette.fill : .clear)
    .onHover { hovering = $0 }
    .opacity(cancelled ? 0 : 1)
    .animation(.easeOut(duration: 0.3), value: cancelled)
  }

  private var cancel: some View {
    Button {
      cancelled = true
      Task {
        do throws(HostError) {
          _ = try await host.run(CancelFollowUp(followUp.id))
        } catch {
          cancelled = false
          showFailure(error)
        }
      }
    } label: {
      Image(systemName: Symbols.cancel)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Palette.inkMuted)
        .frame(width: 22, height: 22)
        .background(Circle().fill(Palette.fillStrong))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .changesData()
    .help(Text(.loci("timers.cancel")))
    .accessibilityLabel(Text(.loci("timers.cancel")))
  }
}
