import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func lociStatus() async -> LociStatus {
    LociStatus(working: await loci.isWorking)
  }

  /// Read from the files each time, which Loci and the person may both have changed.
  public func lociPage() async throws(HostError) -> LociPage {
    let today = Day(containing: environment.now(), in: environment.timeZone)
    let title = itemTitles()
    return try attempt {
      LociPage(
        soul: Soul(parsing: try store.agentText(.soul)),
        memory: MemoryEntry.lines(of: try store.agentText(.memory), title: title),
        profile: MemoryEntry.lines(of: try store.agentText(.profile), title: title),
        today: DayNotes(day: today, parsing: try store.dayNotes(of: today), title: title),
        diaries: store.diaryDays().map { day in
          Diary(day: day, parsing: (try? store.diary(of: day)) ?? "").heading
        },
        together: try together(today: today))
    }
  }

  public func diary(of day: Day) async throws(HostError) -> Diary {
    Diary(day: day, parsing: try attempt { try store.diary(of: day) })
  }

  public func saveSoul(_ command: SaveSoul) async throws(HostError) -> Soul {
    let text = try attempt {
      let text = try Soul.rewriting(try store.agentText(.soul), core: command.core)
      try store.saveAgentText(text, as: .soul)
      return text
    }
    await follow([.loci(.soul)])
    return Soul(parsing: text)
  }

  public func forget(_ command: Forget) async throws(HostError) -> Done {
    let file: AgentFile = command.file == .memory ? .memory : .profile
    try attempt {
      guard let remaining = MemoryEntry.removing(command.line, from: try store.agentText(file)) else {
        throw HostError.notFound(command.line)
      }
      try store.saveAgentText(remaining, as: file)
    }
    await follow([.loci(command.file == .memory ? .memory : .profile)])
    return Done()
  }

  public func avatar() async throws(HostError) -> Avatar? {
    try attempt { try store.avatar() }
  }

  public func setAvatar(_ command: SetAvatar) async throws(HostError) -> Done {
    try attempt { try store.setAvatar(command.avatar) }
    await follow([.loci(.avatar)])
    return Done()
  }

  public func resetAvatar() async throws(HostError) -> Done {
    try attempt { try store.resetAvatar() }
    await follow([.loci(.avatar)])
    return Done()
  }

  private func together(today: Day) throws -> Together {
    let talk = try database.talk()
    let first = talk.first.map { Day(containing: $0, in: environment.timeZone) }
    return Together(
      days: first.map { $0.days(until: today) + 1 } ?? 0, messages: talk.messages,
      itemsReadTogether: talk.itemsTalkedAbout)
  }

  /// The titles of the items in the library, looked up once for a whole page.
  private func itemTitles() -> @Sendable (EntityID) -> String? {
    let titles = Dictionary(
      ((try? database.items()) ?? []).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    return { titles[$0] }
  }
}
