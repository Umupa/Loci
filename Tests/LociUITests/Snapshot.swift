import AppKit
import SwiftUI

/// Renders a view off screen and saves it under `output/snapshots/`, so a change
/// to the interface can be looked at without launching the app.
@MainActor
enum Snapshot {
  enum Appearance: String, CaseIterable {
    case light, dark

    var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
  }

  struct RenderingFailed: Error {}

  @discardableResult
  static func render(_ view: some View, named name: String, size: CGSize, appearance: Appearance) throws -> URL {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.appearance = NSAppearance(named: appearance.name)
    host.frame = CGRect(origin: .zero, size: size)
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
