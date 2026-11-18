/// How fast media plays. `<` and `>` step through these and stop at either end.
enum PlaybackSpeed: Double, CaseIterable {
  case half = 0.5
  case threeQuarters = 0.75
  case normal = 1
  case quarterFaster = 1.25
  case halfFaster = 1.5
  case threeQuartersFaster = 1.75
  case double = 2

  var faster: PlaybackSpeed {
    let all = Self.allCases
    let index = all.firstIndex(of: self) ?? 0
    return all[min(index + 1, all.count - 1)]
  }

  var slower: PlaybackSpeed {
    let all = Self.allCases
    let index = all.firstIndex(of: self) ?? 0
    return all[max(index - 1, 0)]
  }

  /// `1.0×`, `1.25×`, `0.5×`: always at least one decimal, so the label keeps its width when it changes.
  var label: String {
    let hundredths = Int((rawValue * 100).rounded())
    let decimals = hundredths % 10 == 0 ? 1 : 2
    return String(format: "%.\(decimals)f×", rawValue)
  }
}
