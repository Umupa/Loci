import LociModel
import SwiftUI

/// Picks a model from what the model services offer, the models listed under their providers.
struct ModelChoiceMenu: View {
  let groups: [ModelGroup]
  @Binding var selection: ModelChoice?
  /// What the face shows; the selection unless leaving it unchosen follows something else.
  var shown: ModelChoice?
  /// A first item that leaves the choice to the settings.
  var following: LocalizedStringResource?
  /// Shows as a borderless trigger, like the other pickers in a row.
  var plain = false

  var body: some View {
    Menu {
      if let following {
        Button {
          selection = nil
        } label: {
          if selection == nil { Image(systemName: Symbols.done) }
          Text(following)
        }
        Divider()
      }
      ForEach(groups, id: \.provider) { group in
        Section {
          ForEach(group.choices(), id: \.self) { choice in
            Button {
              selection = choice
            } label: {
              if selection == choice { Image(systemName: Symbols.done) }
              Text(verbatim: choice.model)
            }
          }
        } header: {
          ModelWords.name(of: group)
        }
      }
    } label: {
      if plain {
        PlainTriggerLabel { plainFace }
      } else {
        PopupLabel { compactFace }
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize(horizontal: !plain, vertical: false)
  }

  @ViewBuilder
  private var plainFace: some View {
    if let face {
      ModelMark(preset: face.group.preset, name: face.group.name, size: 15, plain: true)
      Text(verbatim: Agents.modelName(face.model)).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
    } else if selection == nil, shown == nil, let following {
      Text(following).font(.system(size: 12.5))
    } else {
      Text(.loci("models.none")).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted)
    }
  }

  @ViewBuilder
  private var compactFace: some View {
    if let face {
      ModelMark(preset: face.group.preset, name: face.group.name, size: 16)
      Text(verbatim: face.model).font(.system(size: 12).monospaced())
    } else if selection == nil, shown == nil, let following {
      Text(following)
    } else {
      Text(.loci("models.none")).foregroundStyle(Palette.inkMuted)
    }
  }

  private var face: (group: ModelGroup, model: String)? {
    guard let choice = shown ?? selection,
      let group = groups.first(where: { $0.provider == choice.provider && $0.models.contains(choice.model) })
    else { return nil }
    return (group, choice.model)
  }
}
