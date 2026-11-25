import Foundation
import LociModel

/// The newest published release of Loci, read from `latest.json`.
public struct ReleaseFeed: Sendable {
  /// The feed on Cloudflare R2.
  public static let loci = URL(string: "https://dl.umupa.fun/loci/latest.json")!

  private let network: any Network
  private let address: URL

  public init(network: any Network, address: URL = Self.loci) {
    self.network = network
    self.address = address
  }

  /// The release the feed describes. Throws why it cannot be read.
  public func latest() async throws(FetchError) -> AppRelease {
    let request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData)
    let (data, _) = try await network.data(for: request)
    let feed: Latest
    do {
      feed = try JSONDecoder().decode(Latest.self, from: data)
    } catch {
      throw FetchError(reason: "the release could not be read: \(error.localizedDescription)")
    }
    guard let version = ReleaseVersion(feed.version), let image = feed.downloads.first,
      feed.sha256.count == 64, feed.sha256.allSatisfy(\.isHexDigit)
    else { throw FetchError(reason: "\(address.host() ?? "the feed") describes no usable release") }
    return AppRelease(
      version: version, image: image, mirrors: Array(feed.downloads.dropFirst()), checksum: feed.sha256.lowercased())
  }

  /// The shape of `latest.json`, written by the release workflow.
  private struct Latest: Decodable {
    let version: String
    let sha256: String
    let downloads: [URL]
  }
}
