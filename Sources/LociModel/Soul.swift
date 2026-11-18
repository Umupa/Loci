/// `SOUL.md`: the core the person may rewrite, and the traits the daily review adds below it.
public struct Soul: Hashable, Codable, Sendable {
  /// Markdown: everything above `## Evolved Traits`.
  public let core: String
  /// Newest first.
  public let traits: [Line<Trait>]

  /// The most traits the review keeps.
  public static let traitLimit = 15
  static let traitsHeading = "## Evolved Traits"

  public init(core: String, traits: [Line<Trait>]) {
    self.core = core
    self.traits = traits
  }

  /// Reads the file. Without a traits heading the whole file is the core.
  public init(parsing text: String) {
    let (core, traits) = Self.split(text)
    self.core = core.trimmingCharacters(in: .whitespacesAndNewlines)
    self.traits = Bullets.pieces(of: traits ?? "").reversed().map { piece in
      switch piece {
      case .item(let line, let text):
        let (day, rest) = Bullets.leadingDay(text)
        return rest.isEmpty ? .text(line) : .entry(Trait(day: day, text: rest))
      case .other(let line):
        return .text(line)
      }
    }
  }

  /// The file with its core replaced and its traits exactly as they were. A core that is blank, or that
  /// holds a traits heading of its own, is refused.
  public static func rewriting(_ text: String, core: String) throws -> String {
    let core = core.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !core.isEmpty else { throw ModelError("the soul is empty") }
    guard split(core).traits == nil else { throw ModelError("the core cannot hold \(traitsHeading)") }
    let traits = split(text).traits ?? ""
    return core + "\n\n" + traitsHeading + "\n" + traits
  }

  /// The text above the traits heading, and the text below it when there is one.
  private static func split(_ text: String) -> (core: String, traits: String?) {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard
      let heading = lines.firstIndex(where: {
        $0.trimmingCharacters(in: .whitespaces).lowercased() == traitsHeading.lowercased()
      })
    else { return (text, nil) }
    return (
      lines[..<heading].joined(separator: "\n"),
      lines[lines.index(after: heading)...].joined(separator: "\n")
    )
  }
}

/// One way Loci has changed, in a sentence, with the day it noticed.
public struct Trait: Hashable, Codable, Sendable {
  public let day: Day?
  public let text: String

  public init(day: Day?, text: String) {
    self.day = day
    self.text = text
  }
}
