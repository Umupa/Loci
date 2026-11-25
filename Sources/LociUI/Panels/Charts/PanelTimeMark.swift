import LociModel
import SwiftUI

/// The time a panel's numbers were got, right of its title: the time alone today, the day before it
/// otherwise. When a source behind it failed its last try, an amber hollow ring stands before it, and
/// hovering says when the numbers were got.
struct PanelTimeMark: View {
  let time: PanelDataTime
  @Environment(\.fixedNow) private var fixedNow
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    let date = time.fetched.date
    let now = fixedNow ?? Date()
    let fetchedAt = date.formatted(date: .abbreviated, time: .shortened)
    HStack(spacing: 5) {
      if time.stale {
        Circle().strokeBorder(Palette.accent, lineWidth: 1.4).frame(width: 6, height: 6)
      }
      Group {
        if Calendar.current.isDate(date, inSameDayAs: now) {
          Text(verbatim: TimeOfDay(of: time.fetched, in: Calendar.current.timeZone).description)
        } else {
          TimerTime.label(date, now: now)
        }
      }
      .contentTransition(.numericText())
    }
    .font(.system(size: 11.5))
    .monospacedDigit()
    .foregroundStyle(Palette.inkFaint)
    .animation(reduceMotion ? nil : Motion.quick, value: time)
    .help(Text(.loci("panels.fetchedAt \(fetchedAt)")))
  }
}
