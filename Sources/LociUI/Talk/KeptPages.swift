import LociModel

/// Which projects' pages stay made beside the chat's, so turning back to one shows it as it was.
enum KeptPages {
  static let projectsKept = 3

  /// The pages `made` so far, in the order they were first made, so a turn moves none of them; the `open`
  /// project's always, and past the limit the oldest made is let go. Projects not `alive` any more go, once
  /// the projects are known.
  static func projects(made: [Project.ID], open: Project.ID?, alive: Set<Project.ID>?) -> [Project.ID] {
    var kept = made.filter { alive?.contains($0) ?? true }
    if let open, !kept.contains(open) { kept.append(open) }
    while kept.count > projectsKept, let oldest = kept.firstIndex(where: { $0 != open }) {
      kept.remove(at: oldest)
    }
    return kept
  }
}
