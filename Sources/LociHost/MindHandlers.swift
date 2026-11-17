import LociModel
import LociStore

extension LocalHost {
  public func mind(of mentor: EntityID) async throws(HostError) -> Mind {
    try attempt { try store.mind(of: mentor) }
  }
}
