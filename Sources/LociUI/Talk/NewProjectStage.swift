import LociModel
import SwiftUI

/// Where a project starts: one large field in the middle of the page, its placeholder turning through a few
/// examples, with a button for another one. Once sent, the field rises and panel skeletons wait under it
/// until the companion has made the project.
struct NewProjectStage: View {
  /// What was sent, once it was.
  let sent: String?
  let send: (String, String?) -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.locale) private var locale
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var text = ""
  @State private var chosenIcon: String?
  @State private var pickingIcon = false
  @State private var hoveringIcon = false
  @State private var example = 0
  @State private var turns = 0.0
  @State private var breathing = false
  @FocusState private var focused: Bool

  static let examples: [LocalizedStringResource] = [
    .loci("projects.exampleFunds"), .loci("projects.exampleTrip"), .loci("projects.exampleInterview"),
    .loci("projects.exampleBook"), .loci("projects.exampleLearn"),
  ]

  private var previewSymbol: String {
    chosenIcon ?? ProjectIcon.inferred(from: text)
  }

  var body: some View {
    VStack(spacing: 26) {
      if sent == nil {
        Button {
          pickingIcon.toggle()
        } label: {
          ProjectSeal(
            symbol: previewSymbol, size: Size.sealLarge, selected: !text.isEmpty || chosenIcon != nil, ghost: false
          )
          .background(
            RoundedRectangle(cornerRadius: Size.sealLarge * 0.28, style: .continuous)
              .fill(hoveringIcon ? Palette.fill : .clear)
          )
          .scaleEffect(breathing && text.isEmpty && chosenIcon == nil && !reduceMotion ? 1.04 : 1)
          .opacity(breathing && text.isEmpty && chosenIcon == nil && !reduceMotion ? 0.65 : 1)
          .contentShape(RoundedRectangle(cornerRadius: Size.sealLarge * 0.28, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .onHover { hoveringIcon = $0 }
        .disabled(!changesAllowed)
        .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
          ProjectIconPicker(selected: previewSymbol) { icon in
            chosenIcon = icon
            pickingIcon = false
          }
        }
        .animation(reduceMotion ? nil : Motion.quick, value: previewSymbol)
        .animation(
          text.isEmpty && chosenIcon == nil && !reduceMotion
            ? .easeInOut(duration: 2.2).repeatForever(autoreverses: true) : Motion.quick,
          value: breathing
        )
        .onAppear { breathing = true }
        .transition(.opacity)
      }
      field
      if sent != nil {
        HStack(alignment: .top, spacing: Spacing.m) {
          PanelSkeleton(sources: .loci)
          PanelSkeleton(sources: .loci)
        }
        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: Spacing.m)))
      }
    }
    .frame(maxWidth: 530)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sent == nil ? .center : .top)
    .padding(.top, sent == nil ? 0 : Spacing.m)
    .padding(.bottom, sent == nil ? Size.newProjectLift : 0)
    .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85), value: sent)
    .task(id: sent == nil) {
      guard sent == nil else { return }
      focused = true
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3))
        if text.isEmpty { next() }
      }
    }
  }

  private var field: some View {
    HStack(spacing: 8) {
      Button(action: next) {
        Image(systemName: "shuffle")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 38, height: 38)
          .background(Circle().fill(Palette.fill))
          .rotationEffect(.degrees(turns))
      }
      .buttonStyle(PressStyle(scale: 0.92))
      .help(Text(.loci("projects.shuffle")))
      .opacity(sent == nil ? 1 : 0)
      ZStack(alignment: .leading) {
        if text.isEmpty, sent == nil {
          Text(Self.examples[example % Self.examples.count])
            .foregroundStyle(Palette.inkFaint)
            .id(example)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
        }
        if let sent {
          Text(verbatim: sent).foregroundStyle(Palette.ink).lineLimit(1)
        } else {
          TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .disabled(!changesAllowed)
            .onSubmit(submit)
        }
      }
      .font(.system(size: 16))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 6)
      Button(action: submit) {
        Image(systemName: "arrow.up")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(ready ? Palette.onAccent : Palette.inkFaint)
          .frame(width: 38, height: 38)
          .background(Circle().fill(ready ? Palette.accent : Palette.fillStrong))
      }
      .buttonStyle(PressStyle(scale: 0.92))
      .disabled(!ready)
      .help(Text(.loci("projects.start")))
    }
    .padding(.horizontal, 10)
    .frame(height: 58)
    .background(Capsule(style: .circular).fill(Palette.surface))
    .overlay(
      Capsule(style: .circular).strokeBorder(sent == nil ? Palette.lineStrong : Palette.accentLine, lineWidth: 1)
    )
    .shadow(color: Palette.liftShadow.opacity(0.4), radius: 22, y: 18)
  }

  private var ready: Bool {
    sent == nil && changesAllowed && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func next() {
    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.55)) {
      example += 1
      turns -= 360
    }
  }

  private func submit() {
    guard ready else { return }
    send(text.trimmingCharacters(in: .whitespacesAndNewlines), chosenIcon)
  }
}
