import Foundation

/// How a moment in a video or audio item reads: minutes and seconds, with hours once there are any.
enum MediaTime {
  /// `11:20`, `1:03:45`. Seconds are cut, not rounded, so the clock never runs ahead of the sound.
  static func text(_ time: Duration) -> String {
    let total = max(0, Int(time.components.seconds))
    let hours = total / 3600
    let minutes = total / 60 % 60
    let seconds = total % 60
    let tail = String(format: "%02d", seconds)
    return hours > 0 ? "\(hours):" + String(format: "%02d", minutes) + ":" + tail : "\(minutes):" + tail
  }

  /// What is left, with a minus sign in front: `−53:42`. A length not known yet reads `--:--`.
  static func remaining(at time: Duration, of length: Duration) -> String {
    length > .zero ? "\u{2212}" + text(max(.zero, length - time)) : unknown
  }

  /// `11:20 / 34:12`.
  static func progress(at time: Duration, of length: Duration) -> String {
    text(time) + " / " + (length > .zero ? text(length) : unknown)
  }

  static let unknown = "--:--"

  static func seconds(_ time: Duration) -> Double {
    Double(time.components.seconds) + Double(time.components.attoseconds) / 1e18
  }
}
