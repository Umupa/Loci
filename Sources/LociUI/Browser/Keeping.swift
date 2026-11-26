import LociModel

/// What was last kept from a page, while the library button and the note under it say how it went: saving
/// from the click on, then saved, stopped with what fixes it, or refused by the host.
struct Keeping: Equatable {
  /// What was chosen, to ask for again after a refusal.
  let chosen: [PageFinds.Find]
  /// The items the library took, in the order they were kept.
  private(set) var items: [EntityID] = []
  /// Why the host would not take what was chosen, or some of it.
  private(set) var refusal: HostError?
  private var answered = false
  /// Items the library has listed since; one that leaves it after was taken back out.
  private var seen: Set<EntityID> = []

  init(chosen: [PageFinds.Find] = []) {
    self.chosen = chosen
  }

  enum State: Equatable {
    /// `nil` when how far along cannot be told.
    case saving(Fraction?)
    /// Readable in the library.
    case saved([Item])
    /// The work on this item stopped; `Fix` gets it going again.
    case stopped(Item, JobLine.Fix, JobLine.Problem?)
    case refused(HostError)
  }

  mutating func took(_ items: [EntityID], refusal: HostError?) {
    self.items = items
    self.refusal = refusal
    answered = true
  }

  mutating func noting(_ library: [Item]) {
    seen.formUnion(library.lazy.map(\.id).filter(items.contains))
  }

  /// `nil` once what was kept has been taken back out of the library.
  func state(library: [Item]?, jobs: [Job]) -> State? {
    guard answered else { return .saving(nil) }
    if let refusal, items.isEmpty { return .refused(refusal) }
    guard let library else { return .saving(nil) }
    let shown = items.compactMap { id in library.first { $0.id == id } }
    let arriving = items.contains { id in !seen.contains(id) && !shown.contains { $0.id == id } }
    if shown.isEmpty { return arriving ? .saving(nil) : nil }
    var shares: [Fraction?] = arriving ? [nil] : []
    var stopped: State?
    for item in shown {
      let job = jobs.first { $0.item == item.id }
      if let job, Self.readable(item, at: job) {
        shares.append(Fraction(1))
        continue
      }
      switch JobLine(job) {
      case .none: shares.append(Fraction(1))
      case .working(_, let share): shares.append(share)
      case .action(let fix, let problem): stopped = stopped ?? .stopped(item, fix, problem)
      }
    }
    if shares.contains(where: { $0 != Fraction(1) }) {
      let known = shares.compactMap(\.self)
      return .saving(
        known.count == shares.count && stopped == nil
          ? Fraction(known.map(\.value).reduce(0, +) / Double(known.count)) : nil)
    }
    if let stopped { return stopped }
    if let refusal { return .refused(refusal) }
    return .saved(shown)
  }

  /// An article or paper reads once its text is in; finding its cover or translating it comes after.
  private static func readable(_ item: Item, at job: Job) -> Bool {
    guard item.kind == .article || item.kind == .paper,
      let stage = Job.Stage.allCases.firstIndex(of: job.stage),
      let text = Job.Stage.allCases.firstIndex(of: .extract)
    else { return false }
    return stage > text
  }
}
