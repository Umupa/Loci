import LociModel
import LociStore

extension LocalHost {
  /// Stops this host and resets its folder: everything but `settings.json` is discarded, the database too
  /// (`Store.reset()`). The host serves nothing afterwards; start a new one over the same folder.
  public func reset() async throws(HostError) {
    await close()
    try attempt { try store.reset() }
  }
}
