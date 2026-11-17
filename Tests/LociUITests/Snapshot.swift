import AppKit
import SwiftUI

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
    locale: Locale = Locale(identifier: "zh-Hans"), settle: Duration = .milliseconds(400)
  ) async throws -> URL {
    let host = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height).environment(\.locale, locale))
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance.name)
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: settle)
    host.layoutSubtreeIfNeeded()

    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderingFailed() }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderingFailed() }

    let file = directory.appending(path: "\(name)-\(appearance.rawValue).png")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: file)
    return file
  }

  private static var directory: URL {
    URL(filePath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "output/snapshots")
  }
}
