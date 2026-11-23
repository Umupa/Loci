import Foundation
import LociModel

/// The texts the app gives Loci: its first soul, the rules every session starts from, and the prompts the
/// app writes for the person. They are part of the app, so a missing one is a broken build, reported as a
/// failed turn rather than a crash.
struct Prompts: Sendable {
  let soul: String
  let previousSoul: String
  let rules: String
  let review: String
  let panel: String
  let course: String

  static func bundled() throws(HostError) -> Prompts {
    Prompts(
      soul: try resource("soul"), previousSoul: try resource("soul-1.7"),
      rules: try resource("rules"), review: try resource("review"),
      panel: try resource("panel"), course: try resource("course"))
  }

  private static func resource(_ name: String) throws(HostError) -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Resources/Loci"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { throw .storage("\(name).md is missing from the app") }
    return text
  }

  /// `AGENTS.md`: the rules, then the soul and the person as they are now.
  func instructions(soul: String, profile: String, name: String) -> String {
    [
      rules.trimmingCharacters(in: .whitespacesAndNewlines),
      "# Your soul (SOUL.md)\n\n" + soul.trimmingCharacters(in: .whitespacesAndNewlines),
      "# The person (USER.md)\n\n" + profile.trimmingCharacters(in: .whitespacesAndNewlines),
      "# Your name\n\n" + (name.isEmpty ? "You have no name yet." : "Your current name is \(name).")
        + " This is the current choice even if an older entry uses another name.",
    ].joined(separator: "\n\n") + "\n"
  }

  /// What the daily review is asked. `since` is when the review before it began, when that was on the day
  /// before: notes written after it are in that day's file and not yet looked back on.
  func review(of day: Day, since previous: (day: Day, at: TimeOfDay)?) -> String {
    let earlier = previous.map { ", and the lines after \($0.at) in `notes/\($0.day).md`" } ?? ""
    return
      review
      .replacing("{{day}}", with: day.description)
      .replacing("{{earlier}}", with: earlier)
      .replacing("{{traitLimit}}", with: String(Soul.traitLimit))
  }

  /// What a panel's refresh is asked: what the panel follows, and the panel as it is now.
  func panel(_ panel: Panel) throws(HostError) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let json: String
    do {
      json = String(decoding: try encoder.encode(panel), as: UTF8.self)
    } catch {
      throw .storage(String(describing: error))
    }
    return
      self.panel
      .replacing("{{name}}", with: panel.name)
      .replacing("{{follow}}", with: panel.follow)
      .replacing("{{json}}", with: json)
  }

  /// A question about a passage, with the passage quoted so Loci sees what the person sees.
  static func ask(_ question: String, about passage: Passage) -> String {
    let quoted = "> " + passage.excerpt.replacing("\n", with: "\n> ")
    return """
      I am reading this passage (\(passage.locator)):

      \(quoted)

      \(question)
      """
  }
}

/// A short, stable digest of a text, to tell whether it changed since it was last shown. Not for security.
enum Fingerprint {
  static func of(_ text: String) -> String {
    let hash = text.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    return String(hash, radix: 16)
  }
}
