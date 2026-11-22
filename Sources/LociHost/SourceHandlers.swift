import Foundation
import LociModel

extension LocalHost {
  public func readSource(_ url: URL) async throws(HostError) -> String {
    try await sources.read(url)
  }

  public func fetchSourceRepository(_ command: FetchSourceRepository) async throws(HostError) -> SourceCheckout {
    try await sources.repository(command)
  }

  public func clearSourceCache() async throws(HostError) -> Done {
    try await sources.clear()
    return Done()
  }
}
