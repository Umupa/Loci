import Foundation
import LociModel

/// The newest published release of Loci, read from `latest.json` at the first place that answers.
public struct ReleaseFeed: Sendable {
  /// Cloudflare R2 first, then the latest GitHub release.
  public static let loci = [
    URL(string: "https://dl.umupa.fun/loci/latest.json")!,
    URL(string: "https://github.com/Umupa/Loci/releases/latest/download/latest.json")!,
  ]

  private let network: any Network
  private let addresses: [URL]

  public init(network: any Network, addresses: [URL] = Self.loci) {
    self.network = network
    self.addresses = addresses
  }

  /// The release the first readable feed describes. Throws why the last place failed when none can be read.
  public func latest() async throws(FetchError) -> AppRelease {
    var failure = FetchError(reason: "there is nowhere to look for releases")
    for address in addresses {
      do {
        return try await release(at: address)
      } catch {
        failure = error
      }
    }
    throw failure
  }

  private func release(at address: URL) async throws(FetchError) -> AppRelease {
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
