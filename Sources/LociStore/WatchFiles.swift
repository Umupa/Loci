import Foundation
import GRDB
import LociModel

extension HomeFiles {
  public func watch() throws -> String {
    try store.optionalText(at: folder.appending(path: "WATCH.md")) ?? ""
  }

  public func saveWatch(_ text: String) throws {
    try store.write(Data(text.utf8), to: folder.appending(path: "WATCH.md"))
  }

  func prepareWatch() throws {
    let path = folder.appending(path: "WATCH.md")
    if try store.optionalText(at: path) == nil { try saveWatch("# Watch\n") }
  }
}

private struct LegacyWatchCondition: Decodable {
  let field: SourceField
  let comparison: String
  let threshold: Double
  let say: String
  let ask: String

  var note: String {
    "When \(field) crosses into \(field) \(comparison) \(threshold), alert me about \(Self.line(say)); ask \(Self.line(ask))."
  }

  static func line(_ text: String) -> String {
    text.split(whereSeparator: \.isNewline).joined(separator: " ")
  }
}

extension Store {
  public func migrateWatch(in database: StoreDatabase) throws {
    let rows: [Row]? = try database.queue.read { db in
      guard try db.tableExists("next_up_condition") else { return nil }
      return try Row.fetchAll(db, sql: "SELECT id, home, body FROM next_up_condition ORDER BY id")
    }
    guard let rows else { return }
    var notes: [String: [String]] = [:]
    for row in rows {
      let condition = try StoreDatabase.decoded(LegacyWatchCondition.self, row["body"])
      let id: String = row["id"]
      notes[row["home"] as String, default: []].append("- \(condition.note) <!-- imported \(id) -->")
    }

    let projects = projects()
    let deleted = setAsideProjects()
    let homes: [(key: String, agent: URL, state: URL)] =
      [("chat", agentFolder, root)]
      + projects.map { ($0.id.description, home(.project($0.id)).folder, projectFolder($0.id)) }
      + deleted.map {
        let base = deletedProject($0)
        return ($0.description, base.appending(path: "agent"), base.appending(path: "state"))
      }
    for home in homes {
      try migrateWatch(in: home.agent, state: home.state, notes: notes.removeValue(forKey: home.key) ?? [])
    }
    if !notes.isEmpty {
      throw StoreError.notFound("The home of an existing watch preference")
    }
    try database.queue.write { db in try db.execute(sql: "DROP TABLE IF EXISTS next_up_condition") }
  }

  private func migrateWatch(in agent: URL, state: URL, notes: [String]) throws {
    var lines = notes
    var panels: [(URL, Data)] = []
    let definitions = files(in: agent.appending(path: Self.panelsFolder), withExtension: "json")
    let copies = files(in: state.appending(path: Self.shownPanelsFolder), withExtension: "json")
    for path in definitions + copies {
      let data = try read(path)
      guard var panel = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        var feed = panel["feed"] as? [String: Any],
        let words = feed.removeValue(forKey: "skip") as? [String]
      else { continue }
      let name = path.deletingPathExtension().lastPathComponent
      let source = feed["source"] as? String ?? name
      lines += words.enumerated().map { index, word in
        "- Treat \(LegacyWatchCondition.line(word)) in \(source) as noise for \(name) (imported preference \(index + 1))."
      }
      panel["feed"] = feed
      panels.append((path, try JSONSerialization.data(withJSONObject: panel, options: [.prettyPrinted, .sortedKeys])))
    }
    if !lines.isEmpty {
      let path = agent.appending(path: "WATCH.md")
      let current = try optionalText(at: path) ?? "# Watch\n"
      var kept = Set(current.components(separatedBy: .newlines))
      let additions = lines.filter { kept.insert($0).inserted }
      if !additions.isEmpty {
        let text = current + (current.hasSuffix("\n") ? "" : "\n") + "\n" + additions.joined(separator: "\n") + "\n"
        try write(Data(text.utf8), to: path)
      }
    }
    for (path, data) in panels { try write(data, to: path) }
  }
}
