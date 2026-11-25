import LociModel
import SwiftUI

/// An approval card: what the companion would put in the calendar or the reminders, with amber light running
/// around it until the person answers. Approved, the light stops, a tick shows and it can be undone.
struct ApprovalCard: View {
  let card: NextUp
  let approval: Approval
  let project: Project?
  let actions: NextUpActions
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.locale) private var locale

  private var approved: Bool { if case .approved = card.state { true } else { false } }
  private var isEvent: Bool { if case .event = approval { true } else { false } }

  var body: some View {
    NextUpFace {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          mark
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: approval.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(Palette.ink)
            HStack(spacing: 5) {
              if let project { ProjectSeal(seal: project.seal, size: 13) }
              Text(verbatim: when)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.inkMuted)
          }
          .lineLimit(1)
          Spacer(minLength: 0)
          if approved {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 18))
              .foregroundStyle(Palette.accent)
              .transition(.scale(scale: 0.4).combined(with: .opacity))
          }
        }
        if changesAllowed { buttons }
      }
      .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 14))
    }
    .overlay { if !approved { TurningEdge() } }
    .help(Text(verbatim: card.what))
    .anchorPreference(key: NextUpAnchors.self, value: .bounds) { NextUpAnchors.Value(cards: [card.id: $0]) }
  }

  @ViewBuilder private var buttons: some View {
    HStack(spacing: 8) {
      if approved {
        Button(.loci("deck.undo")) { actions.undo(card) }.buttonStyle(QuietButtonStyle())
        Spacer(minLength: 0)
        Button {
          actions.set(card, .decline)
        } label: {
          NextUpChoiceFace(symbol: "xmark", tint: nil)
        }
        .buttonStyle(.plain)
        .help(Text(.loci("deck.putAway")))
      } else {
        Button(.loci("deck.decline")) { actions.set(card, .decline) }.buttonStyle(QuietButtonStyle())
        Button(isEvent ? .loci("deck.addToCalendar") : .loci("deck.addReminder")) {
          actions.approve(card)
        }
        .buttonStyle(AmberButtonStyle(fills: true))
      }
    }
  }

  /// A calendar page with the day, or the reminders' checkbox.
  @ViewBuilder private var mark: some View {
    switch approval {
    case .event(let event):
      VStack(spacing: 0) {
        Text(event.start.date, format: .dateTime.weekday(.abbreviated).locale(locale))
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, minHeight: 13)
          .background(Palette.Mark.calendar)
        Text(verbatim: "\(Calendar.current.component(.day, from: event.start.date))")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Palette.ink)
          .frame(maxHeight: .infinity)
      }
      .frame(width: 40, height: 42)
      .background(Palette.canvas)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: Size.hairline))
    case .reminder:
      Image(systemName: "checklist")
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(Palette.accentInk)
        .frame(width: 40, height: 42)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.canvas))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: Size.hairline))
    }
  }

  private func words(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
  }

  /// When, and where it goes: `周日 20:00 · 日历`.
  private var when: String {
    let place: String
    let time: String
    switch approval {
    case .event(let event):
      place = event.calendar ?? words(.loci("deck.calendar"))
      let day = event.start.date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(locale))
      time = event.allDay ? day : day + " " + event.start.date.formatted(.dateTime.hour().minute().locale(locale))
    case .reminder(let reminder):
      place = reminder.list ?? words(.loci("deck.reminders"))
      time = reminder.due.map { $0.date.formatted(.dateTime.month().day().hour().minute().locale(locale)) } ?? ""
    }
    return [time, place].filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

/// A thin border all the way around the card, gray but for an amber stretch that circles it while the card waits.
/// With motion reduced, and in snapshots, it holds still.
private struct TurningEdge: View {
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { context in
      let turns = reduceMotion ? 0.12 : context.date.timeIntervalSinceReferenceDate / Self.period
      RoundedRectangle(cornerRadius: Radius.nextUpCard, style: .continuous)
        .strokeBorder(
          AngularGradient(
            stops: [
              .init(color: Palette.lineStrong, location: 0), .init(color: Palette.lineStrong, location: 0.6),
              .init(color: Palette.accent, location: 0.78), .init(color: Palette.Glow.gold, location: 0.82),
              .init(color: Palette.accent, location: 0.86), .init(color: Palette.lineStrong, location: 1),
            ], center: .center, angle: .degrees(turns.truncatingRemainder(dividingBy: 1) * 360)),
          lineWidth: 1.5)
    }
    .allowsHitTesting(false)
  }

  /// Seconds for the amber stretch to go once around.
  static let period = 3.0
}
