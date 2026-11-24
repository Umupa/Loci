import LociModel
import SwiftUI

/// A provider's mark: its letter on a tile of its own color. No brand logos.
struct ModelMark: View {
  let preset: ModelPreset
  /// One of your own is marked with the first letter of its name.
  var name = ""
  var size: CGFloat = 28
  var faded = false

  var body: some View {
    Text(verbatim: letter)
      .font(.system(size: size * 0.46, weight: .bold))
      .foregroundStyle(preset == .custom ? Palette.ink : ModelMark.letterInk(preset))
      .frame(width: size, height: size)
      .background(
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
          .fill(preset == .custom ? Palette.fillStrong : ModelMark.tile(preset))
      )
      .overlay {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
          .strokeBorder(.white.opacity(0.18), lineWidth: Size.hairline)
      }
      .opacity(faded ? 0.45 : 1)
      .accessibilityHidden(true)
  }

  private var letter: String {
    guard preset == .custom else { return ModelWords.letter(preset) }
    return name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "+"
  }

  static func tile(_ preset: ModelPreset) -> Color {
    switch preset {
    case .openAI: Color(dark: 0x14B48C, light: 0x10A37F)
    case .anthropic: Color(dark: 0xD2805C, light: 0xC8714C)
    case .openRouter: Color(dark: 0x7D7A73, light: 0x6B6862)
    case .deepSeek: Color(dark: 0x5677E0, light: 0x3B5CCC)
    case .kimi: Color(dark: 0xF2EEE6, light: 0x1D1B18)
    case .zhipu: Color(dark: 0x4A70E6, light: 0x2B54D6)
    case .qwen: Color(dark: 0x8268EA, light: 0x6A4CE0)
    case .siliconFlow: Color(dark: 0x9461F2, light: 0x7C3AED)
    case .volcengine: Color(dark: 0x4D82FF, light: 0x2F6BFF)
    case .miniMax: Color(dark: 0xEE5D70, light: 0xE8445A)
    case .custom: Palette.fillStrong
    }
  }

  private static func letterInk(_ preset: ModelPreset) -> Color {
    preset == .kimi ? Color(dark: 0x1D1B18, light: 0xFFFFFF) : .white
  }
}

/// What providers are called and lettered.
enum ModelWords {
  static func name(_ preset: ModelPreset, custom: String = "") -> Text {
    switch preset {
    case .openAI: Text(verbatim: "OpenAI")
    case .anthropic: Text(verbatim: "Anthropic")
    case .openRouter: Text(verbatim: "OpenRouter")
    case .deepSeek: Text(verbatim: "DeepSeek")
    case .kimi: Text(verbatim: "Kimi")
    case .zhipu: Text(.loci("models.zhipu"))
    case .qwen: Text(.loci("models.qwen"))
    case .siliconFlow: Text(.loci("models.siliconFlow"))
    case .volcengine: Text(.loci("models.volcengine"))
    case .miniMax: Text(verbatim: "MiniMax")
    case .custom: custom.isEmpty ? Text(.loci("models.custom")) : Text(verbatim: custom)
    }
  }

  static func name(of group: ModelGroup) -> Text {
    name(group.preset, custom: group.name)
  }

  /// The words a search for a preset matches, in both languages.
  static func searchable(_ preset: ModelPreset) -> [String] {
    let local: [ModelPreset: [String]] = [
      .kimi: ["Moonshot", "月之暗面"], .zhipu: ["Zhipu", "智谱", "GLM"], .qwen: ["Qwen", "通义千问", "百炼", "DashScope"],
      .siliconFlow: ["SiliconFlow", "硅基流动"], .volcengine: ["Volcano", "火山方舟", "Ark", "豆包"],
      .custom: ["Custom", "自定义"],
    ]
    return [preset.rawValue] + (local[preset] ?? [])
  }

  static func letter(_ preset: ModelPreset) -> String {
    switch preset {
    case .openAI, .openRouter: "O"
    case .anthropic: "A"
    case .deepSeek: "D"
    case .kimi: "K"
    case .zhipu: "智"
    case .qwen: "通"
    case .siliconFlow: "硅"
    case .volcengine: "火"
    case .miniMax: "M"
    case .custom: "+"
    }
  }
}

extension Symbols {
  static let models = "cpu"
  static let reveal = "eye"
  static let conceal = "eye.slash"
  static let fetchModels = "arrow.clockwise"
  static let tryModel = "bolt"
  static let saved = "checkmark.circle.fill"
  static let failed = "exclamationmark.circle"
}
