import LociModel
import SwiftUI

/// A project's tab in the bar: its seal, and its name spread out while it is open. A project without a name
/// wears a blank seal, circled in amber while the companion works in it, with a × to drop it; the seal is
/// stamped down the moment it is named.
struct ProjectTab: View {
  let bar: ProjectBar
  let project: Project
  let open: Bool
  let unseen: Bool
  let nameWidth: CGFloat
  let stamp: Int
  /// The symbol its words suggested when it was sent, worn faintly until it is named.
  let suggested: String?
  let actions: ProjectBarActions
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var heldWidth: CGFloat?
  @State private var renaming = false
  @State private var reiconing = false
  @State private var hovering = false
  @State private var named = 0

  var body: some View {
    let revealWidth =
      (open ? max(nameWidth, 1) : (heldWidth ?? Size.projectNameWidest)) + ProjectBarPlan.openLabelPadding
    TabPill(open: open, action: { actions.open(.project(project.id)) }) { hovering in
      HStack(spacing: 0) {
        seal(hovering: hovering)
        if let name = project.name {
          RevealWidth(fraction: open ? 1 : 0, maxWidth: revealWidth) {
            Text(verbatim: name)
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(Palette.ink)
              .lineLimit(1)
              .truncationMode(.tail)
              .padding(.horizontal, 6)
          }
          .opacity(open ? 1 : 0)
          .clipped()
          .accessibilityHidden(!open)
        }
      }
    }
    .overlay(alignment: .topTrailing) {
      if project.name == nil, hovering, changesAllowed {
        DropButton { actions.delete(project.id) }
          .offset(x: 2, y: -1)
          .transition(reduceMotion ? .identity : .scale(scale: 0.6).combined(with: .opacity))
      }
    }
    .onHover { over in withAnimation(reduceMotion ? nil : Motion.quick) { hovering = over } }
    .accessibilityLabel(project.title)
    .help(project.title)
    .onAppear { if open, nameWidth > 0 { heldWidth = nameWidth } }
    .onChange(of: open) { if open, nameWidth > 0 { heldWidth = nameWidth } }
    .onChange(of: nameWidth) { if open, nameWidth > 0 { heldWidth = nameWidth } }
    .onChange(of: project.name == nil) { was, now in if was, !now, !reduceMotion { named += 1 } }
    .contextMenu {
      if changesAllowed {
        ProjectMenuItems(bar: bar, project: project, actions: actions) {
          renaming = true
        } reicon: {
          reiconing = true
        }
      }
    }
    .popover(isPresented: $renaming, arrowEdge: .bottom) {
      RenameField(name: project.name ?? "") { name in
        renaming = false
        actions.rename(project.id, name)
      }
    }
    .popover(isPresented: $reiconing, arrowEdge: .bottom) {
      ProjectIconPicker(selected: project.symbol) { icon in
        reiconing = false
        actions.reicon(project.id, icon)
      }
    }
  }

  @ViewBuilder private func seal(hovering: Bool) -> some View {
    Group {
      if project.name == nil {
        UnnamedSeal(project: project.id, symbol: project.icon ?? suggested)
      } else {
        ProjectSeal(symbol: project.symbol, selected: open || hovering, locked: !project.remembered, unseen: unseen)
          .scaleEffect(!open && hovering && !reduceMotion ? 1.06 : 1)
          .keyframeAnimator(initialValue: Stamp(), trigger: named) { seal, stamp in
            seal.scaleEffect(stamp.scale).blur(radius: stamp.blur)
          } keyframes: { _ in
            KeyframeTrack(\.scale) {
              LinearKeyframe(1.9, duration: 0.01)
              SpringKeyframe(1, duration: 0.55, spring: .bouncy)
            }
            KeyframeTrack(\.blur) {
              LinearKeyframe(3, duration: 0.01)
              LinearKeyframe(0, duration: 0.35)
            }
          }
          .background { InkRing(trigger: named) }
      }
    }
    .sealAnchor(.project(project.id))
    .keyframeAnimator(initialValue: 1.0, trigger: stamp) { seal, scale in
      seal.scaleEffect(scale)
    } keyframes: { _ in
      SpringKeyframe(1.3, duration: 0.16)
      SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
    }
  }

  private struct Stamp {
    var scale = 1.0
    var blur = 0.0
  }
}

/// A seal still without a name: a dashed blank, or the symbol its words suggested shown faintly, circled in
/// amber while the companion has a turn under way there.
struct UnnamedSeal: View {
  /// The project whose turns it follows; `nil` for one not sent yet.
  let project: Project.ID?
  let symbol: String?
  /// Whether it is being made, for one not sent yet.
  var working = false
  @State private var conversation: Feed<Conversation>?

  private var busy: Bool { working || conversation?.value?.turn != nil }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Size.seal * 0.31, style: .continuous)
    ZStack {
      if let symbol {
        Image(systemName: symbol)
          .symbolRenderingMode(.monochrome)
          .font(.system(size: Size.seal * 0.66, weight: .medium))
          .foregroundStyle(Palette.inkMuted)
          .opacity(0.6)
      } else {
        shape.strokeBorder(
          busy ? Palette.lineStrong : Palette.inkFaint,
          style: StrokeStyle(lineWidth: 1.2, dash: busy ? [] : [3, 2]))
      }
    }
    .frame(width: Size.seal, height: Size.seal)
    .overlay {
      if busy { TurningRing(shape: RoundedRectangle(cornerRadius: 9, style: .continuous)).padding(-5) }
    }
    .preference(key: Building.self, value: busy)
    .subscribing(project.map { OneConversation(.project($0)) }, into: $conversation)
  }
}

/// Whether a seal in the bar is being made, for the warm light under the bar.
struct Building: PreferenceKey {
  static let defaultValue = false

  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value || nextValue()
  }
}

/// The ring of amber ink that spreads from a seal as it is stamped down.
private struct InkRing: View {
  let trigger: Int

  var body: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .strokeBorder(Palette.accent, lineWidth: 2)
      .padding(-2)
      .keyframeAnimator(initialValue: Ink(), trigger: trigger) { ring, ink in
        ring.scaleEffect(ink.scale).opacity(ink.opacity)
      } keyframes: { _ in
        KeyframeTrack(\.scale) {
          LinearKeyframe(0.7, duration: 0.01)
          CubicKeyframe(2.1, duration: 0.9)
        }
        KeyframeTrack(\.opacity) {
          LinearKeyframe(0.9, duration: 0.01)
          CubicKeyframe(0, duration: 0.9)
        }
      }
      .allowsHitTesting(false)
  }

  private struct Ink {
    var scale = 1.0
    var opacity = 0.0
  }
}

/// The small × on a seal without a name: drops the project.
private struct DropButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: Symbols.cancel)
        .font(.system(size: 7, weight: .heavy))
        .foregroundStyle(Palette.canvas)
        .frame(width: 15, height: 15)
        .background(Circle().fill(Palette.ink))
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .help(Text(.loci("projects.delete")))
    .accessibilityLabel(Text(.loci("projects.delete")))
  }
}
