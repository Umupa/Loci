import LociModel
import SwiftUI

/// A provider's brand mark, or the initial of a custom provider.
struct ModelMark: View {
  let preset: ModelPreset
  var name = ""
  var size: CGFloat = 28
  var faded = false
  var plain = false
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let artSize = size * scale
    RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
      .fill(plain ? .clear : Palette.fillStrong)
      .overlay {
        if preset == .custom {
          Text(verbatim: name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "+")
            .font(.system(size: size * (plain ? 0.62 : 0.46), weight: .bold))
            .foregroundStyle(Palette.ink)
        } else if let art = MarkArt.model(preset, in: scheme) {
          Image(nsImage: art)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: artSize, height: artSize)
        }
      }
      .frame(width: size, height: size)
      .opacity(faded ? 0.45 : 1)
      .accessibilityHidden(true)
  }

  private var scale: CGFloat {
    if plain {
      return switch preset {
      case .openAI: 1.75
      case .siliconFlow: 1.22
      default: 0.86
      }
    }
    return preset == .openAI ? 1.2 : 0.72
  }
}

/// What providers are called.
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
