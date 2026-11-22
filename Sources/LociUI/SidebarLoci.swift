import LociModel
import SwiftUI

/// Loci at the top of the sidebar: its face and its name, with no row drawn behind them. A thin ring goes
/// round the face while the main conversation or Loci's page is on screen. While Loci works, an amber ring
/// breathes there instead and a faint line under the name says what it is doing.
struct SidebarLoci: View {
  let chosen: Bool
  let work: LociWork?
  let choose: () -> Void
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    Button(action: choose) {
      HStack(spacing: 11) {
        face
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: "Loci").font(.system(size: 16.5, weight: .semibold, design: .serif))
          if let work {
            Text(work.words)
              .font(.system(size: 12))
              .foregroundStyle(Palette.ink.opacity(Self.faint))
              .lineLimit(1)
              .truncationMode(.tail)
              .id(work.said)
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
          }
        }
        .animation(reduceMotion ? nil : Motion.swap, value: work?.said)
        Spacer(minLength: 0)
      }
      .foregroundStyle(Palette.ink)
      .padding(.vertical, Spacing.xxs)
      .padding(.horizontal, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(Text(verbatim: "Loci"))
    .accessibilityAddTraits(chosen ? .isSelected : [])
    .accessibilityValue(work.map { Text($0.words) } ?? Text(verbatim: ""))
  }

  private var face: some View {
    LociAvatar(size: Self.face)
      .padding(Self.gap)
      .overlay {
        ZStack {
          Circle()
            .strokeBorder(Palette.ink.opacity(0.3), lineWidth: 1)
            .opacity(chosen && work == nil ? 1 : 0)
          BreathingRing(color: Tones.accent, width: 1.5, breathing: work != nil, period: 2.8)
            .opacity(work == nil ? 0 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: work == nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: chosen)
      }
  }

  private static let face: CGFloat = 36
  /// Between the face and the ring around it.
  private static let gap: CGFloat = 3.5
  private static let faint = 0.45
}

extension LociWork {
  /// What the line under Loci's name says: an answer the way the conversation says it (C-S1).
  var words: LocalizedStringResource {
    switch said {
    case .unspecified: .loci("sidebar.working")
    case .doing(let doing): doing.words
    case .refreshing(let title): .loci("sidebar.refreshing \(title)")
    case .reviewing: .loci("sidebar.reviewing")
    case .saving: .loci("sidebar.saving")
    }
  }

  /// What is said, without what does not change the words, such as whether the last tool has finished.
  var said: Said {
    switch self {
    case .unspecified: .unspecified
    case .answering(let tool): .doing(tool.map(Doing.init) ?? .thinking)
    case .refreshing(let title): .refreshing(title)
    case .reviewing: .reviewing
    case .saving: .saving
    }
  }

  enum Said: Hashable {
    case doing(Doing)
    case refreshing(String)
    case reviewing, saving, unspecified
  }
}
