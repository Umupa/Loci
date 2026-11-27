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
    guard let version = ReleaseVersion(feed.version), let image = feed.downloads.first, Self.isChecksum(feed.sha256)
    else { throw FetchError(reason: "\(address.host() ?? "the feed") describes no usable release") }
    return AppRelease(
      version: version, image: image, mirrors: Array(feed.downloads.dropFirst()), checksum: feed.sha256.lowercased(),
      archive: feed.archive?.file, manifest: feed.manifest?.file,
      patches: (feed.patches ?? []).compactMap { patch in
        guard let from = ReleaseVersion(patch.from), let file = patch.file else { return nil }
        return ReleasePatch(from: from, file: file)
      },
      notes: (feed.notes ?? []).compactMap { notes in
        ReleaseVersion(notes.version).map { ReleaseNotes(version: $0, section: notes.changes) }
      })
  }

  private static func isChecksum(_ text: String) -> Bool {
    text.count == 64 && text.allSatisfy(\.isHexDigit)
  }

  /// The shape of `latest.json`, written by the release workflow. Releases up to 1.8.8 read only `version`,
  /// `sha256` and `downloads`, which still describe the disk image; the rest is optional.
  private struct Latest: Decodable {
    let version: String
    let sha256: String
    let downloads: [URL]
    let archive: File?
    let manifest: File?
    let patches: [Patch]?
    let notes: [Notes]?
  }

  private struct File: Decodable {
    let sha256: String
    let size: Int64?
    let downloads: [URL]

    var file: ReleaseFile? {
      guard ReleaseFeed.isChecksum(sha256), !downloads.isEmpty else { return nil }
      return ReleaseFile(checksum: sha256.lowercased(), size: size, places: downloads)
    }
  }

  private struct Patch: Decodable {
    let from: String
    let sha256: String
    let size: Int64?
    let downloads: [URL]

    var file: ReleaseFile? { File(sha256: sha256, size: size, downloads: downloads).file }
  }

  private struct Notes: Decodable {
    let version: String
    let changes: String
  }
}
