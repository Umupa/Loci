import AppKit
import LociModel
import SwiftUI

/// The brand artwork shipped with the app, loaded once per image.
@MainActor
enum MarkArt {
  private static var loaded: [String: NSImage] = [:]

  static func agent(_ provider: Provider, in scheme: ColorScheme) -> NSImage? {
    let suffix =
      switch (provider, scheme) {
      case (.pi, .dark), (.codex, .dark), (.cursor, .dark), (.hermes, .dark), (.opencode, .dark): "-dark"
      default: ""
      }
    let fileType =
      switch provider {
      case .antigravity, .codex, .fx, .hermes: "png"
      case .claudeCode, .cursor, .grok, .omp, .opencode, .pi: "svg"
      }
    return image("agent-" + provider.rawValue + suffix, extension: fileType)
  }

  static func component(_ component: Component) -> NSImage? {
    switch component {
    case .ytDlp: image("component-yt-dlp", extension: "png")
    case .ffmpeg: image("component-ffmpeg", extension: "png")
    case .quickJS: nil
    }
  }

  /// A site's mark, drawn in one color to be tinted.
  static func site(_ name: String) -> NSImage? {
    guard let mark = image("site-" + name, extension: "svg") else { return nil }
    mark.isTemplate = true
    return mark
  }

  private static func image(_ name: String, extension fileType: String) -> NSImage? {
    if let image = loaded[name] { return image }
    guard let url = Bundle.module.url(forResource: name, withExtension: fileType),
      let image = NSImage(contentsOf: url)
    else { return nil }
    loaded[name] = image
    return image
  }
}
