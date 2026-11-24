import AppKit
import LociModel
import SwiftUI

/// The brand artwork shipped with the app, loaded once per image.
@MainActor
enum MarkArt {
  private static var loaded: [String: NSImage] = [:]

  static func agent(_ provider: Provider, in scheme: ColorScheme) -> NSImage? {
    let provider = provider == .bundledPi ? .pi : provider
    let suffix =
      switch (provider, scheme) {
      case (.pi, .dark), (.codex, .dark), (.cursor, .dark), (.hermes, .dark), (.opencode, .dark): "-dark"
      default: ""
      }
    let fileType =
      switch provider {
      case .antigravity, .codex, .fx, .hermes: "png"
      case .claudeCode, .cursor, .grok, .omp, .opencode, .pi, .bundledPi: "svg"
      }
    return image("agent-" + provider.rawValue + suffix, extension: fileType)
  }

  static func component(_ component: Component, in scheme: ColorScheme) -> NSImage? {
    switch component {
    case .ytDlp: image("component-yt-dlp", extension: "png")
    case .ffmpeg: image("component-ffmpeg", extension: "png")
    case .quickJS: nil
    case .bundledPi: agent(.bundledPi, in: scheme)
    }
  }

  /// A site's mark, drawn in one color to be tinted.
  static func site(_ name: String) -> NSImage? {
    guard let mark = image("site-" + name, extension: "svg") else { return nil }
    mark.isTemplate = true
    return mark
  }

  /// A connector's mark in its colors, by the connector's id; `nil` for one the app draws no mark for.
  static func connector(_ id: ConnectorID) -> NSImage? {
    connectorArt[id.rawValue].flatMap { image($0, extension: "svg") }
  }

  private static let connectorArt = [
    "notion": "connector-notion", "linear": "connector-linear", "sentry": "connector-sentry",
    "atlassian": "connector-atlassian",
  ]

  private static func image(_ name: String, extension fileType: String) -> NSImage? {
    if let image = loaded[name] { return image }
    guard let url = Bundle.module.url(forResource: name, withExtension: fileType),
      let image = NSImage(contentsOf: url)
    else { return nil }
    loaded[name] = image
    return image
  }
}
