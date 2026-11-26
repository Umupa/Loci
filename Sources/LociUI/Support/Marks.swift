import AppKit
import LociModel
import SwiftUI

/// Brand and system app artwork, loaded once per image.
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

  static func model(_ preset: ModelPreset, in scheme: ColorScheme) -> NSImage? {
    let name = "model-" + preset.rawValue
    let suffix = scheme == .dark ? "-dark" : ""
    return switch preset {
    case .openAI: agent(.codex, in: scheme)
    case .anthropic, .openRouter, .kimi, .siliconFlow: image(name + suffix, extension: "svg")
    case .deepSeek, .volcengine: image(name, extension: "svg")
    case .zhipu, .qwen, .miniMax: image(name, extension: "png")
    case .custom: nil
    }
  }

  static func component(_ component: Component, in scheme: ColorScheme) -> NSImage? {
    switch component {
    case .ytDlp: image("component-yt-dlp", extension: "png")
    case .ffmpeg: image("component-ffmpeg", extension: "png")
    case .quickJS: nil
    case .bundledPi: agent(.bundledPi, in: scheme)
    }
  }

  static func connector(_ id: ConnectorID, in scheme: ColorScheme) -> NSImage? {
    let name = "connector-" + id.rawValue
    let suffix = scheme == .dark ? "-dark" : ""
    return switch id.rawValue {
    case "linear", "github", "sentry", "atlassian": image(name + suffix, extension: "svg")
    case "x": image(name + suffix, extension: "png")
    case "notion": image(name, extension: "svg")
    case "v2ex", "xiaohongshu", "bilibili": image(name, extension: "png")
    case "calendar": application("com.apple.iCal")
    case "reminders": application("com.apple.reminders")
    default: nil
    }
  }

  private static func application(_ identifier: String) -> NSImage? {
    if let image = loaded[identifier] { return image }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
    let image = NSWorkspace.shared.icon(forFile: url.path)
    loaded[identifier] = image
    return image
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
