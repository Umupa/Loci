import Foundation
import LociModel

/// The newest published release of Loci, read from GitHub.
public struct ReleaseFeed: Sendable {
  public static let loci = URL(string: "https://api.github.com/repos/Umupa/Loci/releases/latest")!

  private let network: any Network
  private let address: URL

  public init(network: any Network, address: URL = Self.loci) {
    self.network = network
    self.address = address
  }

  /// The latest release with a disk image, or `nil` when its tag is not a version or it has no disk image.
  public func latest() async throws(FetchError) -> AppRelease? {
    var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, _) = try await network.data(for: request)
    let release: Published
    do {
      release = try JSONDecoder().decode(Published.self, from: data)
    } catch {
      throw FetchError(reason: "the release could not be read: \(error.localizedDescription)")
    }
    guard !release.draft, !release.prerelease, let version = ReleaseVersion(release.tag),
      let image = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
    else { return nil }
    return AppRelease(version: version, package: image.address)
  }

  private struct Published: Decodable {
    let tag: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
      case tag = "tag_name"
      case draft, prerelease, assets
    }
  }

  private struct Asset: Decodable {
    let name: String
    let address: URL

    private enum CodingKeys: String, CodingKey {
      case name
      case address = "browser_download_url"
    }
  }
}
