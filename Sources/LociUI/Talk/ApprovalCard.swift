import LociModel
import SwiftUI

/// An approval card: what the companion would put in the calendar or the reminders, with amber light running
/// around it until the person answers. Approving shows where macOS has it go, with its account, to confirm, or
/// each of one name to pick from; then the light stops, a tick shows and it can be undone.
struct ApprovalCard: View {
  let card: NextUp
  let approval: Approval
  let project: Project?
  let actions: NextUpActions
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.locale) private var locale

  private var approved: Bool { if case .made = card.execution { true } else { false } }
  private var gone: String? { if case .targetGone(let name) = card.execution { name } else { nil } }
  private var found: [ApprovalTarget] { if case .choosing(let found) = card.execution { found } else { [] } }
  /// The one calendar or list found, to confirm: shown whole on its own line.
  private var confirming: ApprovalTarget? { found.count == 1 ? found.first : nil }
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
              .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
              if let project { ProjectSeal(seal: project.seal, size: 13) }
              Text(verbatim: when)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.inkMuted)
            if let only = confirming {
              Label {
                Text(verbatim: Self.place(only))
                  .fixedSize(horizontal: false, vertical: true)
              } icon: {
                Image(systemName: isEvent ? "calendar" : "checklist")
              }
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(Palette.ink)
              .padding(.top, 2)
            }
            if let gone {
              Text(.loci("deck.targetGone \(gone)"))
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.accentInk)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
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
    if found.count > 1 {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(found, id: \.id) { target in
          Button {
            actions.approve(card, .into(target.id))
          } label: {
            Text(verbatim: Self.place(target))
              .font(Typography.button.weight(.medium))
              .foregroundStyle(Palette.ink)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 15)
              .padding(.vertical, 8)
              .frame(minHeight: Size.primaryHeight)
              .background(RoundedRectangle(cornerRadius: Size.primaryHeight / 2, style: .continuous).fill(Palette.fillStrong))
              .contentShape(RoundedRectangle(cornerRadius: Size.primaryHeight / 2, style: .continuous))
          }
          .buttonStyle(PressStyle(scale: 0.97))
        }
      }
    }
    HStack(spacing: 8) {
      if card.execution.isUnderWay {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 32)
      } else if case .made(let made) = card.execution {
        Button(.loci("deck.undo")) { actions.undo(card, made) }.buttonStyle(QuietButtonStyle())
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
        if let only = found.first, found.count == 1 {
          Button(.loci("deck.confirm")) { actions.approve(card, .into(only.id)) }
            .buttonStyle(AmberButtonStyle(fills: true))
        } else if found.isEmpty {
          Button(approveTitle) { actions.approve(card, gone == nil ? .find : .findDefault) }
            .buttonStyle(AmberButtonStyle(fills: true))
        }
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

  private var approveTitle: LocalizedStringResource {
    switch (isEvent, gone != nil) {
    case (true, false): .loci("deck.addToCalendar")
    case (false, false): .loci("deck.addReminder")
    case (true, true): .loci("deck.addToDefaultCalendar")
    case (false, true): .loci("deck.addToDefaultList")
    }
  }

  /// When, from start to end, and where it goes: `11月30日 周日 20:00–21:00 · 家庭`, with the account once it is
  /// written: `· 家庭 · iCloud`. Found and to be confirmed, where it goes is on a line of its own, or on a
  /// button for each of one name.
  private var when: String {
    let named: String
    let time: String
    switch approval {
    case .event(let event):
      named = event.calendar ?? words(.loci("deck.calendar"))
      time = Self.span(from: event.start.date, to: event.end.date, allDay: event.allDay, locale: locale)
    case .reminder(let reminder):
      named = reminder.list ?? words(.loci("deck.reminders"))
      time = reminder.due.map { $0.date.formatted(.dateTime.month().day().hour().minute().locale(locale)) } ?? ""
    }
    let place: String =
      switch card.execution {
      case .choosing(let found) where found.count == 1: ""
      case .writing(_, let target): Self.place(target)
      case .made(let made), .undoing(let made): Self.place(made.into)
      case .waiting, .choosing, .targetGone: named
      }
    return [time, place].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  private static func place(_ target: ApprovalTarget) -> String {
    [target.name, target.source].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  /// The days and times an event takes: one day with its hours, or the first and last day.
  static func span(from start: Date, to end: Date, allDay: Bool, locale: Locale) -> String {
    let day = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated).locale(locale)
    let hour = Date.FormatStyle.dateTime.hour().minute().locale(locale)
    var calendar = Calendar.current
    calendar.locale = locale
    if allDay {
      let last = end.addingTimeInterval(-1)
      return calendar.isDate(start, inSameDayAs: last)
        ? start.formatted(day) : start.formatted(day) + "–" + last.formatted(day)
    }
    if calendar.isDate(start, inSameDayAs: end) {
      return start.formatted(day) + " " + start.formatted(hour) + "–" + end.formatted(hour)
    }
    return start.formatted(day) + " " + start.formatted(hour) + " – " + end.formatted(day) + " " + end.formatted(hour)
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
