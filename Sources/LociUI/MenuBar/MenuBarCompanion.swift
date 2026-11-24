import AppKit
import LociModel
import Observation

/// The companion on this Mac as the menu bar shows it: its name, its face and what it is busy with. It follows
/// the host for as long as the app runs, whether or not a window is open.
@MainActor
@Observable
public final class MenuBarCompanion {
  public private(set) var name = ""
  private(set) var face = LociFace.drawn
  /// `nil` while the companion is idle.
  public private(set) var work: LociWork?
  /// The timer that comes due next and when; `nil` when none will.
  private(set) var next: NextTimer?
  @ObservationIgnored private var watching: [Task<Void, Never>] = []

  public init(host: any LociModel.Host) {
    watching = [
      Task { [weak self] in
        for await feed in host.subscribe(CompanionName()) { self?.name = feed.value ?? "" }
      },
      Task { [weak self] in
        for await feed in host.subscribe(LociWorking()) { self?.work = feed.value?.work }
      },
      Task { [weak self] in
        for await feed in host.subscribe(WatchTimers()) { self?.next = feed.value.flatMap(NextTimer.init) }
      },
      Task { [weak self] in
        for await feed in host.subscribe(LociModel.LociAvatar()) {
          self?.face = (feed.value ?? nil).flatMap { NSImage(data: $0.data) }.map(LociFace.picture) ?? .drawn
        }
      },
    ]
  }

  isolated deinit {
    for task in watching { task.cancel() }
  }
}

/// What comes due next among the schedules and follow-ups: its title, or the follow-up's promise, and when.
struct NextTimer: Equatable {
  let title: String
  let due: Timestamp

  init?(_ timers: Timers) {
    let schedules = timers.schedules.compactMap { entry in entry.next.map { (entry.title, $0) } }
    let followUps = timers.followUps.map { ($0.what, $0.due) }
    guard let soonest = (schedules + followUps).min(by: { $0.1 < $1.1 }) else { return nil }
    title = soonest.0
    due = soonest.1
  }
}
