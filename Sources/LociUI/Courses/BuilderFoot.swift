import LociModel
import SwiftUI

/// The builder's foot: putting it away, and the step to take next — find sources, start writing, start
/// reading. The step is gray until it can be taken; when it can, it turns amber and a ring swells round it
/// twice, inviting a press.
struct BuilderFoot: View {
  let stage: CourseStage
  let canGoOn: Bool
  /// A moment of the invitation, for a snapshot.
  var invitation: Double?
  let later: () -> Void
  let goOn: () -> Void
  @State private var invited = 0

  var body: some View {
    HStack(spacing: 10) {
      Spacer(minLength: 0)
      Button(action: later) {
        Text(.loci("course.later"))
          .font(.system(size: 13.5, weight: .medium))
          .foregroundStyle(Palette.ink)
          .padding(.horizontal, 18)
          .frame(height: 34)
          .background(Capsule().fill(Palette.fillStrong))
      }
      .buttonStyle(AnswerPress(scale: 0.96))
      Button(action: goOn) {
        Text(stage.next)
          .id(stage)
          .transition(.opacity.combined(with: .offset(y: 6)))
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(canGoOn ? Palette.onAccent : Palette.inkFaint)
          .padding(.horizontal, 18)
          .frame(minWidth: 110)
          .frame(height: 34)
          .background(Capsule().fill(canGoOn ? Palette.accent : Palette.fillStrong))
          .background { invitationRing }
      }
      .buttonStyle(AnswerPress(scale: 0.96))
      .disabled(!canGoOn)
      .changesData()
      .animation(Motion.swap, value: stage)
      .animation(.easeOut(duration: 0.3), value: canGoOn)
    }
    .padding(.horizontal, 18)
    .frame(height: Size.builderFoot)
    .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
    .onChange(of: canGoOn, initial: true) { _, can in if can { invited += 1 } }
  }

  @ViewBuilder private var invitationRing: some View {
    if let invitation {
      Capsule().stroke(Palette.accent.opacity(0.22), lineWidth: 6 * sin(invitation * .pi)).padding(-3)
    } else {
      Capsule().fill(.clear)
        .keyframeAnimator(initialValue: 0.0, trigger: invited) { capsule, swell in
          capsule.overlay { Capsule().stroke(Palette.accent.opacity(0.22), lineWidth: 6 * swell).padding(-3 * swell) }
        } keyframes: { _ in
          CubicKeyframe(1, duration: 0.56)
          CubicKeyframe(0, duration: 0.84)
          CubicKeyframe(1, duration: 0.56)
          CubicKeyframe(0, duration: 0.84)
        }
    }
  }
}

extension CourseStage {
  /// What the button at the builder's foot does from this stage.
  var next: LocalizedStringResource {
    switch self {
    case .goal: .loci("course.findSources")
    case .sources: .loci("course.startWriting")
    case .writing: .loci("course.startReading")
    }
  }
}
