import LociModel
import SwiftUI

/// How Loci feels and how tired it is: its word for the mood, a scale each for how good it feels and how
/// much energy it has, and where its tiredness stands. Why it feels so shows on hover.
struct FeelingLine: View {
  let feeling: Feeling

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.l) {
      mood
      Scale(symbol: Symbols.valence, value: feeling.valence, label: .loci("loci.valence"))
      Scale(symbol: Symbols.energy, value: feeling.energy, label: .loci("loci.energy"))
      tiredness
    }
  }

  private var mood: some View {
    (feeling.word.map { Text(verbatim: $0) } ?? Text(.loci("loci.resting")))
      .font(.system(size: 19, weight: .medium, design: .serif))
      .foregroundStyle(Palette.ink)
      .lineLimit(1)
      .help(feeling.why.map { Text(verbatim: $0) } ?? Text(.loci("loci.restingWhy")))
  }

  private var tiredness: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: Self.symbol(feeling.tiredness))
        .font(.system(size: 12.5))
        .foregroundStyle(feeling.tiredness == .awake ? Palette.inkMuted : Palette.accent)
      Text(Self.name(feeling.tiredness))
        .font(.system(size: 13))
        .foregroundStyle(Palette.ink)
    }
    .help(Text(verbatim: "\(feeling.fatigue) / 100"))
  }

  static func symbol(_ tiredness: Tiredness) -> String {
    switch tiredness {
    case .awake: Symbols.awake
    case .tired: Symbols.tired
    case .sleepy: Symbols.sleepy
    case .asleep: Symbols.asleep
    }
  }

  static func name(_ tiredness: Tiredness) -> LocalizedStringResource {
    switch tiredness {
    case .awake: .loci("loci.awake")
    case .tired: .loci("loci.tired")
    case .sleepy: .loci("loci.sleepy")
    case .asleep: .loci("loci.asleep")
    }
  }
}

/// A score from 0 to 10 as ten short bars, the first `value` of them inked.
private struct Scale: View {
  let symbol: String
  let value: Score
  let label: LocalizedStringResource

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: symbol)
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.inkMuted)
      HStack(spacing: 2) {
        ForEach(Score.range.dropFirst(), id: \.self) { step in
          Capsule()
            .fill(step <= value.value ? Palette.ink : Palette.lineStrong)
            .frame(width: 3, height: 11)
        }
      }
      .animation(Motion.arrive, value: value)
    }
    .help(Text(label))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(label))
    .accessibilityValue(Text(verbatim: "\(value.value) / 10"))
  }
}

extension Symbols {
  static let valence = "face.smiling"
  static let energy = "bolt"
  static let awake = "sun.max"
  static let tired = "cloud"
  static let sleepy = "moon"
  static let asleep = "moon.zzz"
}
