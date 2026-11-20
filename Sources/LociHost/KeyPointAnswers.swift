import Foundation
import LociModel

/// Reads and checks the key points in an agent's answer.
enum KeyPointAnswers {
  private struct Point: Decodable {
    let start: Double?
    let end: Double?
    let passage: Int?
    let title: String
    let reason: String
  }

  private struct Answer: Decodable {
    let keyPoints: [Point]
  }

  /// Key points within units `range` of `units`, as many as `count` allows, in order and apart. When
  /// `among` is given, each one is at the place of one of those.
  static func points(
    in reply: String, of units: KeyPointUnits, within range: Range<Int>, count: ClosedRange<Int>,
    among: [KeyPoint]? = nil
  ) throws(TranscriptAnswerError) -> [KeyPoint] {
    let answer = try TranscriptAnswers.decode(Answer.self, from: reply)
    guard count.contains(answer.keyPoints.count) else {
      throw TranscriptAnswerError(
        "\(answer.keyPoints.count) key points came back for \(count.lowerBound)…\(count.upperBound)")
    }
    var points: [KeyPoint] = []
    for point in answer.keyPoints {
      var place = try self.place(of: point, in: units, within: range)
      if let among {
        guard let match = among.first(where: { same($0.place, place) }) else {
          throw TranscriptAnswerError("a key point is not one of the candidates")
        }
        place = match.place
      }
      do {
        points.append(try KeyPoint(place: place, title: point.title, reason: point.reason))
      } catch {
        throw TranscriptAnswerError("\(error)")
      }
    }
    let sorted = points.sorted { order($0.place) < order($1.place) }
    do {
      _ = try KeyPoints(points: sorted, choice: .standard)
    } catch {
      throw TranscriptAnswerError("\(error)")
    }
    return sorted
  }

  private static func place(of point: Point, in units: KeyPointUnits, within range: Range<Int>)
    throws(TranscriptAnswerError) -> KeyPoint.Place
  {
    switch units {
    case .sentences(let segments):
      guard let start = point.start, let end = point.end else {
        throw TranscriptAnswerError("a key point has no start or end")
      }
      let from = segments[range.lowerBound].start - .seconds(1)
      let to = (segments[range.upperBound - 1].end) + .seconds(1)
      let span: TimeSpan
      do {
        span = try TimeSpan(start: TranscriptAnswers.time(max(start, 0)), end: TranscriptAnswers.time(end))
      } catch {
        throw TranscriptAnswerError("a key point ends before it starts")
      }
      guard span.start >= from, (span.end ?? span.start) <= to else {
        throw TranscriptAnswerError("a key point at \(start)s–\(end)s is outside the transcript")
      }
      return .time(span)
    case .passages(let passages):
      guard let number = point.passage, range.contains(number - 1) else {
        throw TranscriptAnswerError("a key point names a passage that is not there")
      }
      do {
        return .passage(try KeyPoint.Passage(number: number, text: passages[number - 1]))
      } catch {
        throw TranscriptAnswerError("\(error)")
      }
    }
  }

  private static func order(_ place: KeyPoint.Place) -> Duration {
    switch place {
    case .time(let span): span.start
    case .passage(let passage): .seconds(passage.number)
    }
  }

  private static func same(_ one: KeyPoint.Place, _ other: KeyPoint.Place) -> Bool {
    switch (one, other) {
    case (.time(let a), .time(let b)):
      near(a.start, b.start) && near(a.end ?? a.start, b.end ?? b.start)
    case (.passage(let a), .passage(let b)): a.number == b.number
    default: false
    }
  }

  private static func near(_ one: Duration, _ other: Duration) -> Bool {
    one - other <= .seconds(1) && other - one <= .seconds(1)
  }
}
