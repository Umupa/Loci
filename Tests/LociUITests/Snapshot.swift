import AppKit
import SwiftUI
import Testing

@testable import LociUI

/// Renders a view off screen and saves it under `output/snapshots/`, so a change
/// to the interface can be looked at without launching the app.
///
/// The view is placed in a window that is never shown, so `.task` and `.onAppear` run and subscriptions
/// can deliver before the picture is taken. System materials and the window frame do not render off screen.
@MainActor
enum Snapshot {
  enum Appearance: String, CaseIterable {
    case light, dark

    var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
  }

  struct RenderingFailed: Error {}

  static let windowSize = CGSize(width: 1040, height: 640)

  @discardableResult
  static func render(
    _ view: some View, named name: String, size: CGSize = windowSize, appearance: Appearance,
    locale: Locale = Locale(identifier: "zh-Hans"), settle: Duration = .milliseconds(400),
    until ready: (@MainActor (NSWindow) -> Bool)? = nil, steady: Bool = false
  ) async throws -> URL {
    let (host, window) = show(view, size: size, appearance: appearance, locale: locale)
    defer { window.orderOut(nil) }
    let bitmap: NSBitmapImageRep
    if let ready, steady {
      bitmap = try await self.steady(host, in: window, named: name, when: ready)
    } else if let ready {
      try await eventually("\(name) to be ready") { ready(window) }
      bitmap = try picture(of: host, in: window)
    } else {
      try await Task.sleep(for: settle)
      bitmap = try picture(of: host, in: window)
    }
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderingFailed() }

    let file = directory.appending(path: "\(name)-\(appearance.rawValue).png")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: file)
    return file
  }

  /// The picture once `ready` holds and the picture has stopped changing: the same three times in a row, 50 ms
  /// apart. What a view shows after its data arrives, such as covers asked for once a list appears, changes the
  /// picture, so the wait goes on until it is all drawn.
  private static func steady(
    _ host: NSView, in window: NSWindow, named name: String, when ready: @MainActor (NSWindow) -> Bool
  ) async throws -> NSBitmapImageRep {
    let deadline = ContinuousClock.now + .seconds(60)
    var last: (bitmap: NSBitmapImageRep, data: Data)?
    var streak = 0
    var notReady = 0
    var changed = 0
    var checks = 0
    while true {
      guard ContinuousClock.now < deadline else {
        throw TimedOut(
          waitingFor: "\(name) to settle", seen: "checked \(checks) times, not ready \(notReady), changed \(changed)")
      }
      try await Task.sleep(for: .milliseconds(50))
      checks += 1
      guard ready(window) else {
        notReady += 1
        streak = 0
        continue
      }
      let bitmap = try picture(of: host, in: window)
      guard let pixels = bitmap.bitmapData else { throw RenderingFailed() }
      let data = Data(bytes: pixels, count: bitmap.bytesPerPlane)
      if let last, last.data != data { changed += 1 }
      streak = data == last?.data ? streak + 1 : 0
      last = (bitmap, data)
      if streak >= 2 { return bitmap }
    }
  }

  private static func show(
    _ view: some View, size: CGSize, appearance: Appearance, locale: Locale
  ) -> (NSView, NSWindow) {
    if !Stage.seated {
      Issue.record("Mark the suite `.onStage`: its windows share the main thread with every other test.")
    }
    let host = NSHostingView(
      rootView:
        view
        .frame(width: size.width, height: size.height)
        .environment(\.locale, locale)
        .environment(\.suppressMotion, true)
        .transaction { transaction in
          transaction.animation = nil
          transaction.disablesAnimations = true
        })
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance.name)
    window.contentView = host
    window.orderBack(nil)
    return (host, window)
  }

  private static func picture(of host: NSView, in window: NSWindow) throws -> NSBitmapImageRep {
    host.layoutSubtreeIfNeeded()
    let bitmap = try Self.bitmap(of: host)
    drawChildWindows(of: window, onto: bitmap)
    return bitmap
  }

  /// What `view` draws, at two pixels a point whatever screen the Mac has, so a picture and what a test measures
  /// in it are the same on a Retina Mac and on a CI runner without a display.
  static func bitmap(of view: NSView) throws -> NSBitmapImageRep {
    let size = view.bounds.size
    guard
      let blank = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int((size.width * 2).rounded(.up)),
        pixelsHigh: Int((size.height * 2).rounded(.up)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let bitmap = blank.retagging(with: .sRGB)
    else { throw RenderingFailed() }
    bitmap.size = size
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
  }

  /// Panels a view floats over the window, such as the bar over a selection, drawn where they sit.
  private static func drawChildWindows(of window: NSWindow, onto bitmap: NSBitmapImageRep) {
    guard let children = window.childWindows, !children.isEmpty else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    for child in children {
      guard let view = child.contentView, let picture = try? Self.bitmap(of: view) else { continue }
      picture.draw(
        in: window.convertFromScreen(child.frame), from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: true, hints: nil)
    }
  }

  private static var directory: URL {
    URL(filePath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "output/snapshots")
  }
}
