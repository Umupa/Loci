import AVFoundation
import LociModel
import UniformTypeIdentifiers

/// Media downloaded on another Mac, played by asking its host for each range of bytes the player wants.
///
/// The player reads through a scheme of its own, so every request comes here instead of to the network. A
/// request the player gives up on, as when the reader jumps elsewhere, stops being read.
@MainActor
final class RangedMedia: NSObject, AVAssetResourceLoaderDelegate {
  static let scheme = "loci-media"
  /// How much one command asks for, so a long read can be given up part way and the player can start early.
  static let chunk = 512 * 1024

  private let item: EntityID
  private let info: MediaFileInfo
  private let host: any LociModel.Host
  private let url: URL
  private var reading: [ObjectIdentifier: Task<Void, Never>] = [:]

  /// The extension of the file on the other Mac, which says what is in it.
  nonisolated var fileExtension: String { info.fileExtension }

  init?(item: EntityID, info: MediaFileInfo, host: any LociModel.Host) {
    var parts = URLComponents()
    parts.scheme = Self.scheme
    parts.host = "item"
    parts.path = "/\(item).\(info.fileExtension)"
    guard let url = parts.url else { return nil }
    self.item = item
    self.info = info
    self.host = host
    self.url = url
  }

  /// An asset whose bytes all come through this object, which the asset keeps for as long as it plays.
  func asset() -> AVURLAsset {
    let asset = AVURLAsset(url: url)
    asset.resourceLoader.setDelegate(self, queue: DispatchQueue.main)
    return asset
  }

  /// The ranges to read for a request: from where the player is up to, to where it asked to stop, in chunks.
  static func chunks(from start: Int64, to end: Int64) -> [(offset: Int64, length: Int)] {
    stride(from: start, to: end, by: chunk).map { offset in (offset, Int(min(Int64(chunk), end - offset))) }
  }

  nonisolated func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    MainActor.assumeIsolated { start(loadingRequest) }
    return true
  }

  nonisolated func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    MainActor.assumeIsolated { reading.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel() }
  }

  private func start(_ request: AVAssetResourceLoadingRequest) {
    if let content = request.contentInformationRequest {
      content.contentType = UTType(filenameExtension: info.fileExtension)?.identifier
      content.contentLength = info.byteCount
      content.isByteRangeAccessSupported = true
    }
    guard let data = request.dataRequest else {
      request.finishLoading()
      return
    }
    let end =
      data.requestsAllDataToEndOfResource
      ? info.byteCount : min(info.byteCount, data.requestedOffset + Int64(data.requestedLength))
    let key = ObjectIdentifier(request)
    reading[key] = Task { [host, item] in
      defer { reading[key] = nil }
      do throws(HostError) {
        for range in Self.chunks(from: data.currentOffset, to: end) {
          guard !Task.isCancelled else { return }
          let bytes = try await host.run(ReadMediaBytes(item: item, offset: range.offset, length: range.length))
          guard !Task.isCancelled else { return }
          data.respond(with: bytes)
          if bytes.count < range.length { break }
        }
        request.finishLoading()
      } catch {
        if !Task.isCancelled { request.finishLoading(with: error) }
      }
    }
  }
}
