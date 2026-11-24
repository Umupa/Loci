import Foundation
import LociModel

/// `loci connector …`: the person's connected services, which only read.
enum ConnectorRequest: Hashable, Sendable {
  case list(ConnectorID?)
  case call(ConnectorID, tool: String, arguments: String)

  static let usage =
    "loci connector list [<connector>] | loci connector call <connector> <tool> ['<JSON arguments>'] | "
    + "loci connector call gh <gh words that only read>"

  static func parse(_ words: [String]) throws(UsageError) -> ConnectorRequest {
    switch (words.first, words.count) {
    case ("list", 1): return .list(nil)
    case ("list", 2): return .list(ConnectorID(words[1]))
    case ("call", 3...) where words[1] == "gh":
      let args = String(
        decoding: (try? JSONEncoder().encode(["args": Array(words.dropFirst(2))])) ?? Data(), as: UTF8.self)
      return .call(ConnectorID("github"), tool: "gh", arguments: args)
    case ("call", 3...):
      let arguments = words.dropFirst(3).joined(separator: " ").trimmingCharacters(in: .whitespaces)
      let given = arguments.isEmpty ? "{}" : arguments
      guard let data = given.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
      else { throw UsageError("The arguments are one JSON object, in single quotes: '{\"query\": \"…\"}'. \(usage)") }
      return .call(ConnectorID(words[1]), tool: words[2], arguments: given)
    default: throw UsageError(usage)
    }
  }
}

extension Tool {
  func connector(_ request: ConnectorRequest, json: Bool) async throws(Failure) -> Outcome {
    switch request {
    case .list(let only):
      let reply = try await line.run(ListConnectors())
      if json { return .worked(Self.text(reply)) }
      let connectors = try Failure.decoding([Connector].self, from: reply)
      guard let only else {
        guard !connectors.isEmpty else {
          return .worked("No connectors yet. The person connects them on the Connectors page of your companion page.")
        }
        return .worked(connectors.map(ConnectorWords.line).joined(separator: "\n\n"))
      }
      guard let connector = connectors.first(where: { $0.id == only }) else {
        return .failed("There is no connector \(only). Run `loci connector list` to see them.")
      }
      return .worked(ConnectorWords.detail(connector))
    case .call(let connector, let tool, let arguments):
      let reply = try await line.run(CallConnector(connector, tool: tool, arguments: arguments))
      if json { return .worked(Self.text(reply)) }
      return .worked(try Failure.decoding(String.self, from: reply))
    }
  }
}

/// What `loci connector` prints, for Loci to read.
enum ConnectorWords {
  static func line(_ connector: Connector) -> String {
    let who = connector.account.map { ", \($0)" } ?? ""
    let head = "\(connector.id)  \(connector.name)\(who)"
    if case .needsReconnecting(let why) = connector.status {
      return head + "\n    needs reconnecting (\(why)); the person reconnects it on the Connectors page"
    }
    guard !connector.tools.isEmpty else { return head + "\n    no tool it marks read-only, so nothing to read with" }
    return head + "\n" + connector.tools.map { "    \($0.name)  \(firstLine($0.description))" }.joined(separator: "\n")
  }

  static func detail(_ connector: Connector) -> String {
    ([line(connector).components(separatedBy: "\n")[0]]
      + connector.tools.map { "\n\($0.name)\n  \(firstLine($0.description))\n  arguments: \($0.inputSchema)" })
      .joined(separator: "\n")
  }

  private static func firstLine(_ text: String) -> String {
    let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    return line.count > 160 ? String(line.prefix(157)) + "…" : line
  }
}
