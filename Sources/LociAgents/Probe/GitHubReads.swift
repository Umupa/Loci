import Foundation

/// The `gh` commands that only read, which the app runs for the companion: anything else is refused before
/// `gh` starts, with the reason.
public enum GitHubReads {
  /// The subcommands that read, by command.
  static let reads: [String: Set<String>] = [
    "pr": ["list", "view", "diff", "checks", "status"],
    "issue": ["list", "view", "status"],
    "repo": ["view", "list"],
    "release": ["list", "view"],
    "run": ["list", "view"],
    "workflow": ["list", "view"],
    "search": ["repos", "issues", "prs", "code", "commits"],
    "label": ["list"],
  ]

  /// Flags of `gh api` that send something, or make the request anything but a GET.
  static let apiWrites: Set<String> = ["-f", "-F", "--field", "--raw-field", "--input"]

  /// Why `gh` may not run with these arguments; `nil` when they only read.
  public static func refusal(_ arguments: [String]) -> String? {
    guard let command = arguments.first else { return "Give gh a command, such as [\"pr\", \"view\", \"12\"]." }
    if let web = arguments.first(where: { $0 == "--web" || $0 == "-w" }) {
      return "gh \(command) \(web) opens a browser; connectors only read."
    }
    if command == "api" { return apiRefusal(Array(arguments.dropFirst())) }
    guard let subcommands = reads[command] else {
      return "gh \(command) is not a command that only reads. Allowed: \(allowed)."
    }
    guard let subcommand = arguments.dropFirst().first, subcommands.contains(subcommand) else {
      let given = arguments.dropFirst().first.map { " \($0)" } ?? ""
      return "gh \(command)\(given) would change something or is not one that only reads; for \(command), only "
        + subcommands.sorted().joined(separator: ", ") + "."
    }
    return nil
  }

  private static func apiRefusal(_ rest: [String]) -> String? {
    guard let endpoint = rest.first(where: { !$0.hasPrefix("-") }) else { return "gh api needs an endpoint." }
    if endpoint == "graphql" { return "gh api graphql can change things; use a REST endpoint with GET." }
    for (index, flag) in rest.enumerated() {
      let name = flag.split(separator: "=", maxSplits: 1).first.map(String.init) ?? flag
      let joined = !flag.hasPrefix("--") && flag.count > 2 && (flag.hasPrefix("-f") || flag.hasPrefix("-F"))
      if apiWrites.contains(name) || joined {
        return "gh api \(name) sends data and turns the request into a POST; connectors only send GET."
      }
      let next = index + 1 < rest.count ? rest[index + 1] : ""
      if name == "-H" || name == "--header", (flag.contains("=") ? flag : next).lowercased().contains("method-override")
      {
        return "gh api with a method-override header is not a GET; connectors only send GET."
      }
      let method: String
      if name == "-X" || name == "--method" {
        method = flag.contains("=") ? String(flag.split(separator: "=", maxSplits: 1)[1]) : next
      } else if flag.hasPrefix("-X"), flag.count > 2 {
        method = String(flag.dropFirst(2))
      } else {
        continue
      }
      if method.uppercased() != "GET" { return "gh api \(name) \(method) is not a GET; connectors only send GET." }
    }
    return nil
  }

  private static var allowed: String {
    reads.keys.sorted().map { "\($0) \(reads[$0]?.sorted().joined(separator: "|") ?? "")" }.joined(separator: "; ")
      + "; api (GET only)"
  }
}
