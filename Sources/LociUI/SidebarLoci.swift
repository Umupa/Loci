import LociModel
import SwiftUI

/// The companion at the top of the sidebar, like the first chat in a chat app: its face with its dot, its
/// name, and under it what it is doing, or else the last thing it said in the chat. A thin ring goes round the
/// face while the chat or its home page is on screen. While it works, an amber ring breathes there instead.
struct SidebarLoci: View {
  @Environment(\.companionName) private var name
  @Environment(\.companionNow) private var now
  let chosen: Bool
  let choose: () -> Void
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    Button(action: choose) {
      HStack(spacing: 11) {
        face
        VStack(alignment: .leading, spacing: 1) {
          label.lineLimit(1).font(.system(size: 16.5, weight: .semibold, design: .serif))
          if let line = now.sidebarLine {
            line
              .font(.system(size: 12))
              .foregroundStyle(Palette.ink.opacity(Self.faint))
              .lineLimit(1)
              .truncationMode(.tail)
              .id(lineKey)
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
          }
        }
        .animation(reduceMotion ? nil : Motion.swap, value: lineKey)
        Spacer(minLength: 0)
      }
      .foregroundStyle(Palette.ink)
      .padding(.vertical, Spacing.xxs)
      .padding(.horizontal, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(label)
    .accessibilityAddTraits(chosen ? .isSelected : [])
    .accessibilityValue(now.sidebarLine ?? Text(verbatim: ""))
  }

  private var label: Text { name.isEmpty ? Text(.loci("companion.title")) : Text(verbatim: name) }

  /// What the line says, so it changes over only when the words do.
  private var lineKey: String {
    if let work = now.work { return "\(work.said)" }
    return now.presence?.lastSaid ?? ""
  }

  private var face: some View {
    LociAvatar(size: Self.face)
      .padding(Self.gap)
      .overlay {
        ZStack {
          Circle()
            .strokeBorder(Palette.ink.opacity(0.3), lineWidth: 1)
            .opacity(chosen && now.work == nil ? 1 : 0)
          BreathingRing(color: Tones.accent, width: 1.5, breathing: now.work != nil, period: 2.8)
            .opacity(now.work == nil ? 0 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: now.work == nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: chosen)
      }
      .presenceDot(now.tone, side: Self.face + Self.gap * 2, ring: Palette.sidebarRing)
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
    case .doing(let doing): doing.words
    case .refreshing(let title): .loci("sidebar.refreshing \(title)")
    case .reviewing: .loci("sidebar.reviewing")
    case .looking(let title): .loci("sidebar.looking \(title)")
    case .saving: .loci("sidebar.saving")
    }
  }

  /// What is said, without what does not change the words, such as whether the last tool has finished.
  var said: Said {
    switch self {
    case .unspecified: .doing(.working)
    case .answering(let tool): .doing(tool.map(Doing.init) ?? .thinking)
    case .refreshing(let title): .refreshing(title)
    case .reviewing: .reviewing
    case .looking(let title): .looking(title)
    case .saving: .saving
    }
  }

  enum Said: Hashable {
    case doing(Doing)
    case refreshing(String)
    case looking(String)
    case reviewing, saving
  }
}
