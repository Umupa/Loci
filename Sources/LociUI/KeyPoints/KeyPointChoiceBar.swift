import LociModel
import SwiftUI

/// Over the key points: the model they are picked with, how many, and picking them again.
struct KeyPointChoiceBar: View {
  @Binding var choice: KeyPointChoice
  /// The model picking would use now; `nil` when the model services are not configured for it.
  let model: ModelChoice?
  let picking: Bool
  let pick: () -> Void
  @State private var options: Feed<ModelOptions>?

  var body: some View {
    HStack(spacing: Spacing.xs) {
      ModelChoiceMenu(
        groups: options?.value?.groups ?? [],
        selection: Binding {
          choice.model
        } set: {
          choice = KeyPointChoice(model: $0, count: choice.count)
        },
        shown: model, following: .loci("models.followToolModel"))
      Spacer(minLength: 0)
      CountSegments(
        count: Binding {
          choice.count
        } set: {
          choice = KeyPointChoice(model: choice.model, count: $0)
        })
      Button(action: pick) {
        Image(systemName: Symbols.restart)
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: Size.iconButton, height: Size.iconButton)
          .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
      .disabled(picking || model == nil)
      .opacity(picking || model == nil ? 0.4 : 1)
      .help(Text(.loci("keypoints.pickAgain")))
      .accessibilityLabel(Text(.loci("keypoints.pickAgain")))
    }
    .subscribing(AvailableModels(), into: $options)
  }
}

/// How many key points to pick, as a small segmented control of their ranges.
private struct CountSegments: View {
  @Binding var count: KeyPointCount
  @Namespace private var thumb

  var body: some View {
    HStack(spacing: 0) {
      ForEach(KeyPointCount.allCases, id: \.self) { option in
        let chosen = option == count
        Button {
          withAnimation(Motion.quick) { count = option }
        } label: {
          Text(verbatim: "\(option.range.lowerBound)–\(option.range.upperBound)")
            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            .foregroundStyle(chosen ? Palette.ink : Palette.inkMuted)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background {
              if chosen {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                  .fill(Palette.thumb)
                  .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                  .matchedGeometryEffect(id: "thumb", in: thumb)
              }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(KeyPointWords.count(option)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
      }
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fillStrong))
  }
}

/// The face of a popup: its value with the up-and-down chevrons, on a raised capsule.
struct PopupLabel<Label: View>: View {
  @ViewBuilder let label: () -> Label
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 6) {
      label()
      Image(systemName: Symbols.popup).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Palette.inkFaint)
    }
    .font(.system(size: 12.5))
    .foregroundStyle(Palette.ink)
    .lineLimit(1)
    .padding(.leading, 9)
    .padding(.trailing, 8)
    .frame(height: 26)
    .background(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(hovering ? Palette.fillStrong : Palette.fill)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    )
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
  }
}
