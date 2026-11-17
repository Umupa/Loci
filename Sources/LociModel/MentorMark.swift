extension Mentor {
  /// The signs the app draws for mentors; a mentor's `avatar` names one.
  public enum Mark: String, CaseIterable, Sendable {
    case ember, luna, hourglass, lyra, seal, iris, north, wisp, dew, quill, sage, key
  }

  /// The signs the app draws for courses.
  public enum CourseMark: String, CaseIterable, Sendable {
    case book, orbit, grid, wave, layers, graph, steps, pulse, hex, prompt, bars, knot
  }

  /// The sign `avatar` names, or, for a name this version does not draw, one that stays the same for this mentor.
  public var mark: Mark {
    Mark(rawValue: avatar) ?? Self.steady(Mark.allCases, for: id.description)
  }

  /// The sign of the mentor's course, which stays the same for this mentor.
  public var courseMark: CourseMark {
    Self.steady(CourseMark.allCases, for: "course " + id.description)
  }

  /// One of `choices`, always the same for the same `key`, on every run and every Mac.
  private static func steady<Choice>(_ choices: [Choice], for key: String) -> Choice {
    let hash = key.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    return choices[Int(hash % UInt64(choices.count))]
  }
}

extension MentorColor {
  /// The colour of `palette` closest in hue, which is how a mentor coloured by an earlier version is shown.
  public var nearestInPalette: MentorColor {
    if Self.palette.contains(self) { return self }
    let hue = self.hue
    return Self.palette.min { hueDistance($0.hue, hue) < hueDistance($1.hue, hue) } ?? self
  }

  /// The hue as a fraction of a turn, from 0 up to 1.
  var hue: Double {
    let (r, g, b) = (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
    let (high, low) = (max(r, g, b), min(r, g, b))
    guard high > low else { return 0 }
    let span = high - low
    let sixths =
      switch high {
      case r: (g - b) / span
      case g: 2 + (b - r) / span
      default: 4 + (r - g) / span
      }
    return (sixths / 6 + 1).truncatingRemainder(dividingBy: 1)
  }

  private func hueDistance(_ first: Double, _ second: Double) -> Double {
    let apart = abs(first - second)
    return min(apart, 1 - apart)
  }
}
