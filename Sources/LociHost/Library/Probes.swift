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
    let cover: FetchedFile?
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

extension LibraryContext {
  /// The last way something was taken in, or the first default.
  var lastChoice: ImportChoice {
    var choice = settings.importChoice ?? .first(readerLanguage: targetLanguage, speechModel: speechModel)
    if let language = translationSettings.language { choice.translation?.language = language }
    return choice
  }

  /// How an item was taken in; `nil` for one taken in before choices were kept.
  func choice(of item: EntityID) -> ImportChoice? {
    try? store.importChoice(of: item)
  }
}
