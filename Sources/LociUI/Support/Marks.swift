import AppKit
import LociModel
import SwiftUI

/// The agents' logos shipped with the app, loaded once each.
@MainActor
enum MarkArt {
  private static var loaded: [String: NSImage] = [:]

  static func agent(_ provider: Provider) -> NSImage? { image("agent-" + provider.rawValue) }

  private static func image(_ name: String) -> NSImage? {
    if let image = loaded[name] { return image }
    guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else { return nil }
    loaded[name] = image
    return image
  }
}
