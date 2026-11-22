import AppKit
import LociModel
import Testing

@testable import LociUI

@MainActor
struct CoverWashTests {
  @Test func aSquareCoversWashBlursAwayItsLettering() throws {
    let cover = NSImage(size: NSSize(width: 400, height: 400), flipped: false) { rect in
      NSColor.black.setFill()
      rect.fill()
      NSColor.white.setFill()
      NSRect(x: 0, y: 0, width: 200, height: 400).fill()
      return true
    }
    let wash = try #require(CoverWash.of(cover))
    let bitmap = NSBitmapImageRep(cgImage: try #require(wash.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    let middle = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
    let brightness = middle.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
    #expect(brightness > 0.15 && brightness < 0.85)
    #expect(bitmap.pixelsWide <= 96)
  }

  @Test func aWidePodcastCoverGetsASmallWash() async throws {
    let library = try SampleLibrary()
    let host = FakeHost(try Sample(problems: false), library: library)
    let picture = try #require(await Covers().load(library.podcast, pixels: 256, from: host))
    #expect(picture.wash?.size == CGSize(width: 64, height: 64))
  }

  @Test func aListThumbnailIsDecodedAtTheDisplaySize() async throws {
    let library = try SampleLibrary()
    let host = FakeHost(try Sample(problems: false), library: library)
    let covers = Covers()

    let thumbnail = try #require(await covers.load(library.video, pixels: 80, from: host))
    let gallery = try #require(await covers.load(library.video, pixels: 512, from: host))

    #expect(max(thumbnail.image.size.width, thumbnail.image.size.height) == 80)
    #expect(max(gallery.image.size.width, gallery.image.size.height) > 80)
    #expect(max(gallery.image.size.width, gallery.image.size.height) <= 512)
    #expect(thumbnail.bytes * 16 < gallery.bytes)
  }

  @Test func aFullCacheKeepsTheMostRecentlyUsedCoverAndReloadsAnEvictedCover() async throws {
    let library = try SampleLibrary()
    let host = FakeHost(try Sample(problems: false), library: library)
    let covers = Covers(countLimit: 2)
    let styles = [library.video, library.podcast, library.article]
    for item in styles.prefix(2) {
      _ = try #require(await covers.load(item, pixels: 80, from: host))
    }
    let recent = try #require(covers.image(of: library.video.id))
    let firstEpisodeCover = try #require(await covers.load(library.podcast, pixels: 80, from: host))
    #expect(covers.image(of: library.video.id) === recent)

    _ = try #require(await covers.load(library.article, pixels: 80, from: host))
    #expect(covers.image(of: library.video.id) === recent)
    #expect(covers.image(of: library.podcast.id) == nil)

    let secondEpisodeCover = try #require(await covers.load(library.podcast, pixels: 80, from: host))
    #expect(secondEpisodeCover.image !== firstEpisodeCover.image)
  }

  @Test func largePicturesDisplaceOlderCoversBeforeTheCountLimit() async throws {
    let library = try SampleLibrary()
    let host = FakeHost(try Sample(problems: false), library: library)
    let covers = Covers(byteLimit: 120 * 1024)
    let otherEpisode = try #require(library.items.first { $0.id != library.podcast.id && ItemKind($0.kind) == .audio })

    let first = try #require(await covers.load(library.podcast, pixels: 128, from: host))
    let second = try #require(await covers.load(otherEpisode, pixels: 128, from: host))

    #expect(first.bytes + second.bytes > 120 * 1024)
    #expect(covers.image(of: library.podcast.id) == nil)
    #expect(covers.image(of: otherEpisode.id) === second.image)
  }
  @Test func switchingViewsKeepsThePictureAlreadyBeingRead() async throws {
    let library = try SampleLibrary()
    let host = DelayedCoverHost(base: FakeHost(try Sample(problems: false), library: library))
    let covers = Covers()
    let firstView = Task { await covers.load(library.video, pixels: 512, from: host) }
    try await eventually("the cover request to begin") { host.waiting != nil }

    firstView.cancel()
    host.release()
    _ = await firstView.value

    #expect(covers.image(of: library.video.id) != nil)
  }
}

@MainActor
private final class DelayedCoverHost: LociModel.Host {
  let base: FakeHost
  private(set) var waiting: CheckedContinuation<Void, Never>?

  init(base: FakeHost) { self.base = base }

  func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply {
    await withCheckedContinuation { waiting = $0 }
    guard !Task.isCancelled else { throw .offline }
    return try await base.run(command)
  }

  func release() {
    waiting?.resume()
    waiting = nil
  }

  nonisolated func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>> {
    base.subscribe(subscription)
  }

  func upload(_ file: LocalFile) async throws(HostError) -> Upload { try await base.upload(file) }
  func localFile(_ place: LocalPlace) async -> LocalFile? { await base.localFile(place) }
}
