import Foundation
import LociModel
import SwiftUI

extension Every {
  /// `每小时`, `每天 21:00`, `每周一 09:00`.
  var words: Text {
    switch self {
    case .hour: Text(.loci("timers.hourly"))
    case .day(let at): Text(joining: Text(.loci("timers.daily")), Text(verbatim: " \(at.description)"))
    case .week(let day, let at):
      Text(joining: Text(.loci("timers.weekly")), day.name, Text(verbatim: " \(at.description)"))
    }
  }

  /// The choices a schedule's menu offers, with `self` among them.
  var choices: [Every] {
    let nine = TimeOfDay(hour: 9, minute: 0)
    let common =
      [Every.hour] + [nine, TimeOfDay(hour: 21, minute: 0)].compactMap { $0.map { Every.day(at: $0) } }
      + [nine.map { Every.week(.monday, at: $0) }].compactMap { $0 }
    return common.contains(self) ? common : common + [self]
  }
}

extension Weekday {
  /// The short name in the interface's language: `周一`, `Mon`.
  var name: Text {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let sunday = Date(timeIntervalSince1970: 3 * 86_400)
    let day = calendar.date(byAdding: .day, value: rawValue - 1, to: sunday) ?? sunday
    return Text(day, format: Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated))
  }
}

/// When a timer comes due or a run started, said as close to now as reads naturally: `今天 21:00`,
/// `明天 09:00`, `周五 10:00` within the week, otherwise the date.
enum TimerTime {
  static func label(_ date: Date, now: Date, calendar: Calendar = .current) -> Text {
    let time = Text(verbatim: TimeOfDay(of: Timestamp(date), in: calendar.timeZone).description)
    let days =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
      ).day ?? 0
    let day: Text =
      switch days {
      case 0: Text(.loci("day.today"))
      case 1: Text(.loci("day.tomorrow"))
      case -1: Text(.loci("day.yesterday"))
      case 2...6: Text(date, format: .dateTime.weekday(.abbreviated))
      default: Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
      }
    return Text(joining: day, Text(verbatim: " "), time)
  }
}

extension EnvironmentValues {
  /// The moment times are told against when it is fixed, as in a snapshot; `nil` is the clock.
  @Entry var fixedNow: Date?
}
