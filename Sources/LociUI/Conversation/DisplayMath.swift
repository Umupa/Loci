/// Display formulas a mentor writes as `$$…$$` or `\[…\]`, on one line or across several, turned into
/// ```` ```math ```` blocks before Markdown sees them, so that no Markdown rule can take the TeX apart and
/// each one is typeset centred on a line of its own.
enum DisplayMath {
  static func fenced(_ markdown: String) -> String {
    var lines: [Substring] = []
    var formula: [Substring]?
    var closing = ""
    var fence: Substring?
    for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if var open = formula {
        if let end = trimmed.range(of: closing) {
          open.append(Substring(trimmed[..<end.lowerBound]))
          lines += block(open)
          let after = trimmed[end.upperBound...].trimmingCharacters(in: .whitespaces)
          if !after.isEmpty { lines.append(Substring(after)) }
          formula = nil
        } else {
          open.append(line)
          formula = open
        }
        continue
      }
      if let open = fence {
        if trimmed.hasPrefix(open) { fence = nil }
        lines.append(line)
        continue
      }
      if let marker = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
        fence = Substring(marker)
        lines.append(line)
        continue
      }
      guard let (opening, close) = Self.delimiters.first(where: { trimmed.hasPrefix($0.0) }) else {
        lines.append(line)
        continue
      }
      let rest = trimmed.dropFirst(opening.count)
      if let end = rest.range(of: close) {
        lines += block([rest[..<end.lowerBound]])
        let after = rest[end.upperBound...].trimmingCharacters(in: .whitespaces)
        if !after.isEmpty { lines.append(Substring(after)) }
      } else {
        formula = [rest]
        closing = close
      }
    }
    if let formula {
      lines.append(Substring(Self.delimiters.first { $0.1 == closing }?.0 ?? ""))
      lines += formula
    }
    return lines.joined(separator: "\n")
  }

  private static let delimiters = [("$$", "$$"), (#"\["#, #"\]"#)]

  private static func block(_ lines: [Substring]) -> [Substring] {
    let tex = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return ["", "```math"] + tex.map { Substring($0) } + ["```", ""]
  }
}
