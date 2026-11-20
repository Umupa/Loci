import Foundation
import LociMedia
import LociModel

/// Links read a moment ago for the import panel, so taking one in does not read the page again. Only the
/// last few are kept.
actor Probes {
  static let kept = 8

  struct Probe: Sendable {
    let info: MediaInfo
    let json: Data
    let cover: Cover?
  }

  private var probes: [(url: URL, probe: Probe)] = []

  func keep(_ probe: Probe, for url: URL) {
    probes.removeAll { $0.url == url }
    probes.append((url, probe))
    if probes.count > Self.kept { probes.removeFirst(probes.count - Self.kept) }
  }

  /// The probe of `url`, which is then forgotten.
  func take(_ url: URL) -> Probe? {
    guard let index = probes.firstIndex(where: { $0.url == url }) else { return nil }
    return probes.remove(at: index).probe
  }
}

/// A cover picture as fetched, with the file extension it is kept under.
struct Cover: Sendable {
  let data: Data
  let fileExtension: String
}

extension LibraryContext {
  /// The picture at `thumbnail`; `nil` when it cannot be had.
  func cover(at thumbnail: URL?) async -> Cover? {
    guard let thumbnail, let (data, response) = try? await media.network.data(for: URLRequest(url: thumbnail))
    else { return nil }
    let fromType = response.mimeType.flatMap { $0.hasPrefix("image/") ? String($0.dropFirst(6)) : nil }
    let fileExtension = (fromType ?? thumbnail.pathExtension).replacingOccurrences(of: "jpeg", with: "jpg")
    return Cover(data: data, fileExtension: fileExtension.isEmpty ? "jpg" : fileExtension)
  }

  /// The last way something was taken in, or the first default.
  var lastChoice: ImportChoice {
    settings.importChoice ?? .first(readerLanguage: targetLanguage, speechModel: speechModel)
  }

  /// How an item was taken in; `nil` for one taken in before choices were kept.
  func choice(of item: EntityID) -> ImportChoice? {
    try? store.importChoice(of: item)
  }
}
