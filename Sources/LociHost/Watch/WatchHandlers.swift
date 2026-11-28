import LociModel
import LociStore

extension LocalHost {
  /// Read from the file each time, which the companion and the person may both have changed.
  public func watch(of home: Home) async throws(HostError) -> String {
    try attempt {
      try known(home)
      return try store.home(home).watch()
    }
  }

  public func saveWatch(_ command: SaveWatch) async throws(HostError) -> Done {
    try attempt {
      try known(command.home)
      try store.home(command.home).saveWatch(command.text)
    }
    await follow([.loci(.watch)])
    return Done()
  }

  private func known(_ home: Home) throws {
    if let project = home.project { _ = try store.project(project) }
  }
}
