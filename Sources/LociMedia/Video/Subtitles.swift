import Foundation
import LociModel

/// Reads WebVTT, which is what yt-dlp converts every site's subtitles to.
public enum Subtitles {
  /// One segment per cue. Markup is dropped, and lines a rolling caption repeats from the cue before are
  /// kept only once.
  public static func segments(fromWebVTT text: String) -> [Transcript.Segment] {
    var segments: [Transcript.Segment] = []
    var previous: [String] = []
    let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
    for block in blocks {
      let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
      guard let timing = lines.firstIndex(where: { $0.contains("-->") }),
        let (start, end) = times(lines[timing])
      else { continue }
      let spoken = lines[(timing + 1)...].map(clean).filter { !$0.isEmpty }
      let fresh = spoken.filter { !previous.contains($0) }
      if !spoken.isEmpty { previous = spoken }
      let words = fresh.joined(separator: " ")
      guard !words.isEmpty, end > start, let segment = try? Transcript.Segment(start: start, end: end, text: words)
      else { continue }
      if let last = segments.last, segment.start < last.start { continue }
      segments.append(segment)
    }
    return segments
  }

  private static func times(_ line: String) -> (Duration, Duration)? {
    let parts = line.components(separatedBy: "-->")
    guard parts.count == 2, let start = time(parts[0]),
      let end = time(String(parts[1].split(separator: " ", omittingEmptySubsequences: true).first ?? ""))
    else { return nil }
    return (start, end)
  }

  /// `01:02:03.456`, `02:03.456`, or with a comma as SRT writes it.
  private static func time(_ text: String) -> Duration? {
    let fields = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
      .split(separator: ":")
    guard (2...3).contains(fields.count), let seconds = Double(fields.last ?? "") else { return nil }
    let whole = fields.dropLast().compactMap { Int($0) }
    guard whole.count == fields.count - 1 else { return nil }
    let minutes = whole.reduce(0) { $0 * 60 + $1 }
    return .milliseconds(Int(((Double(minutes) * 60 + seconds) * 1000).rounded()))
  }

  private static func clean(_ line: String) -> String {
    line.replacing(/<[^>]*>/, with: "")
      .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
      .trimmingCharacters(in: .whitespaces)
  }
}
