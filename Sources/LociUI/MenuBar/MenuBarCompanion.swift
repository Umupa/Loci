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
