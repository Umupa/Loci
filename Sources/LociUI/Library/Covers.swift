import AppKit
import ImageIO
import LociModel
import SwiftUI

/// Decoded covers for the window, bounded by their pixel storage and kept in order of use.
@MainActor
@Observable
final class Covers {
  private struct Request: Hashable {
    let item: EntityID
    let pixels: Int
  }

  private struct Entry {
    let picture: CoverPicture?

    var bytes: Int { picture.map { $0.bytes + CoverWash.byteBudget } ?? 0 }
  }

  private let countLimit: Int
  private let byteLimit: Int
  private var cached: [Request: Entry] = [:]
  @ObservationIgnored private var order: [Request] = []
  @ObservationIgnored private var pending: [Request: Task<CoverPicture?, Never>] = [:]
  @ObservationIgnored private var bytes = 0
  private(set) var revision = 0

  init(countLimit: Int = 96, byteLimit: Int = 12 * 1024 * 1024) {
    self.countLimit = countLimit
    self.byteLimit = byteLimit
  }

  func image(of item: EntityID) -> NSImage? {
    guard
      let best = cached.keys.filter({ $0.item == item && cached[$0]?.picture != nil })
        .max(by: { $0.pixels < $1.pixels })
    else { return nil }
    touch(best)
    return cached[best]?.picture?.image
  }

  /// The host has a new user-selected cover, so mounted views fetch it at their display size.
  func invalidate(_ item: EntityID) {
    for key in order.filter({ $0.item == item }) { forget(key) }
    for key in pending.keys.filter({ $0.item == item }) {
      pending.removeValue(forKey: key)?.cancel()
    }
    revision += 1
  }

  /// Returns an existing picture at this size or keeps listening while a visible cover is still being fetched.
  func load(_ item: Item, pixels: Int, from host: any LociModel.Host) async -> CoverPicture? {
    let key = Request(item: item.id, pixels: pixels)
    let startedAt = revision
    if let entry = cached[key] {
      touch(key)
      if let picture = entry.picture { return picture }
    } else if let picture = await read(key, from: host) {
      return picture
    }

    guard !Task.isCancelled, revision == startedAt else { return nil }
    for await feed in host.subscribe(ItemCover(item: item.id)) {
      guard !Task.isCancelled, revision == startedAt else { return nil }
      if let picture = cached[key]?.picture {
        touch(key)
        return picture
      }
      if case .value(let data?) = feed, let image = await Self.decode(data, pixels: pixels) {
        guard !Task.isCancelled, revision == startedAt else { return nil }
        let picture = CoverPicture(image)
        remember(picture, for: key)
        return picture
      }
    }
    return nil
  }

  private func read(_ key: Request, from host: any LociModel.Host) async -> CoverPicture? {
    if let task = pending[key] { return await task.value }
    let task = Task { () -> CoverPicture? in
      defer { if !Task.isCancelled { pending[key] = nil } }
      do {
        let data = try await host.run(ReadCover(item: key.item))
        let image: CGImage? = if let data { await Self.decode(data, pixels: key.pixels) } else { nil }
        guard !Task.isCancelled else { return nil }
        let picture = image.map(CoverPicture.init)
        remember(picture, for: key)
        return picture
      } catch {
        return nil
      }
    }
    pending[key] = task
    return await task.value
  }

  @concurrent nonisolated private static func decode(_ data: Data, pixels: Int) async -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(
      source, 0,
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: pixels,
      ] as CFDictionary)
  }

  private func touch(_ key: Request) {
    order.removeAll { $0 == key }
    order.append(key)
  }

  private func remember(_ picture: CoverPicture?, for key: Request) {
    let entry = Entry(picture: picture)
    if let previous = cached.updateValue(entry, forKey: key) { bytes -= previous.bytes }
    bytes += entry.bytes
    touch(key)
    while cached.count > countLimit || bytes > byteLimit, let oldest = order.first {
      forget(oldest)
    }
  }

  private func forget(_ key: Request) {
    if let entry = cached.removeValue(forKey: key) { bytes -= entry.bytes }
    order.removeAll { $0 == key }
  }
}

@MainActor
final class CoverPicture {
  let image: NSImage
  let bytes: Int
  lazy var wash = CoverWash.of(image)

  init(_ picture: CGImage) {
    image = NSImage(cgImage: picture, size: .zero)
    bytes = picture.bytesPerRow * picture.height
  }
}

extension EnvironmentValues {
  @Entry var covers: Covers?
}
