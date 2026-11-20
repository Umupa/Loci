import AppKit
import Foundation
import SwiftUI

/// How subtitles look over the picture, kept on this Mac: a preset, the translation's and the original's
/// lettering, which of the two goes on top, and how far above the foot of the picture they sit. Which lines
/// show at all is the `SubtitleMode`.
struct SubtitleStyle: Equatable {
  /// Where the style is remembered.
  static let key = "subtitleStyle"

  var preset: Preset
  var translation: Lettering
  var original: Lettering
  var order: BilingualOrder
  /// From the foot of the picture, as a share of its height in percent.
  var lift: Int

  static let lifts = 0...40
  static let sizes = 12...40

  static let standard = SubtitleStyle(
    preset: .big, translation: Lettering(font: .pingFang, size: 23, color: .yellow, bold: true),
    original: Lettering(font: .pingFang, size: 17, color: .white, bold: false), order: .translationAbove, lift: 6)

  /// Picks `preset`, which also sets the translation's lettering to suit it.
  mutating func choose(_ preset: Preset) {
    self.preset = preset
    switch preset {
    case .big:
      translation.size = 23
      translation.bold = true
      translation.color = .yellow
    case .outline, .band, .glass:
      translation.size = 21
      translation.bold = preset != .glass
      translation.color = .white
    }
  }

  mutating func raise(by step: Int) {
    lift = min(max(lift + step, Self.lifts.lowerBound), Self.lifts.upperBound)
  }

  enum Preset: String, Codable, CaseIterable {
    /// Letters with a dark edge, nothing behind them.
    case outline
    /// A dark band behind each line.
    case band
    /// Large bold letters with a soft shadow.
    case big
    /// Frosted glass behind each line.
    case glass

    var name: LocalizedStringResource {
      switch self {
      case .outline: .loci("caption.outline")
      case .band: .loci("caption.band")
      case .big: .loci("caption.big")
      case .glass: .loci("caption.glass")
      }
    }
  }

  /// The translation's or the original's lettering.
  struct Lettering: Codable, Equatable {
    var font: SubtitleFont
    /// In points over a picture 880 points wide.
    var size: Int
    var color: SubtitleColor
    var bold: Bool

    mutating func resize(by step: Int) {
      size = min(max(size + step, SubtitleStyle.sizes.lowerBound), SubtitleStyle.sizes.upperBound)
    }
  }

  /// Which of the two lines goes on top when both show.
  enum BilingualOrder: String, Codable, CaseIterable {
    case translationAbove, originalAbove
  }
}

extension SubtitleStyle: Codable {
  private enum CodingKeys: String, CodingKey {
    case preset, translation, original, order, lift
  }

  /// What cannot be read is the standard's.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let standard = Self.standard
    preset = (try? container.decode(Preset.self, forKey: .preset)) ?? standard.preset
    translation = (try? container.decode(Lettering.self, forKey: .translation)) ?? standard.translation
    original = (try? container.decode(Lettering.self, forKey: .original)) ?? standard.original
    order = (try? container.decode(BilingualOrder.self, forKey: .order)) ?? standard.order
    lift = (try? container.decode(Int.self, forKey: .lift)) ?? standard.lift
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(preset, forKey: .preset)
    try container.encode(translation, forKey: .translation)
    try container.encode(original, forKey: .original)
    try container.encode(order, forKey: .order)
    try container.encode(lift, forKey: .lift)
  }
}

extension SubtitleStyle: RawRepresentable {
  init?(rawValue: String) {
    guard let style = try? JSONDecoder().decode(SubtitleStyle.self, from: Data(rawValue.utf8)) else { return nil }
    self = style
  }

  var rawValue: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
  }
}

/// The faces subtitles can be set in.
enum SubtitleFont: String, Codable, CaseIterable {
  case pingFang, hiragino, songti, newYork, rounded

  var name: LocalizedStringResource {
    switch self {
    case .pingFang: .loci("typeface.pingFang")
    case .hiragino: .loci("typeface.hiragino")
    case .songti: .loci("typeface.songti")
    case .newYork: .loci("typeface.newYork")
    case .rounded: .loci("typeface.rounded")
    }
  }

  func font(size: CGFloat, bold: Bool, heavy: Bool) -> Font {
    let weight: Font.Weight = bold ? (heavy ? .heavy : .bold) : .medium
    switch self {
    case .pingFang: return .custom("PingFang SC", size: size).weight(weight)
    case .hiragino: return .custom("Hiragino Sans GB", size: size).weight(weight)
    case .songti: return .custom("Songti SC", size: size).weight(weight)
    case .newYork: return .system(size: size, weight: weight, design: .serif)
    case .rounded: return .system(size: size, weight: weight, design: .rounded)
    }
  }
}

/// The colors subtitles can be.
enum SubtitleColor: String, Codable, CaseIterable {
  case white, gray, yellow, amber, blue

  var color: Color {
    switch self {
    case .white: Color(nsColor: NSColor(rgb: 0xFFFFFF))
    case .gray: Color(nsColor: NSColor(rgb: 0xD9D6D0))
    case .yellow: Color(nsColor: NSColor(rgb: 0xFFD27A))
    case .amber: Color(nsColor: NSColor(rgb: 0xEBA53A))
    case .blue: Color(nsColor: NSColor(rgb: 0x9FD3FF))
    }
  }

  var name: LocalizedStringResource {
    switch self {
    case .white: .loci("tint.white")
    case .gray: .loci("tint.gray")
    case .yellow: .loci("tint.yellow")
    case .amber: .loci("tint.amber")
    case .blue: .loci("tint.blue")
    }
  }
}

/// The three ways both languages can show, as one choice: translation on top, original on top, or only the
/// translation.
enum Bilingual: CaseIterable {
  case translationAbove, originalAbove, translationOnly

  init(mode: SubtitleMode, order: SubtitleStyle.BilingualOrder) {
    switch (mode, order) {
    case (.translation, _): self = .translationOnly
    case (_, .translationAbove): self = .translationAbove
    case (_, .originalAbove): self = .originalAbove
    }
  }

  /// Sets the mode and the order to this.
  func apply(to mode: inout SubtitleMode, _ order: inout SubtitleStyle.BilingualOrder) {
    switch self {
    case .translationAbove:
      mode = .both
      order = .translationAbove
    case .originalAbove:
      mode = .both
      order = .originalAbove
    case .translationOnly: mode = .translation
    }
  }

  var name: LocalizedStringResource {
    switch self {
    case .translationAbove: .loci("caption.translationAbove")
    case .originalAbove: .loci("caption.originalAbove")
    case .translationOnly: .loci("caption.translationOnly")
    }
  }
}
