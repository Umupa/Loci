import LociModel
import SwiftUI

/// A new project before it is sent: only this page's, nothing is made until it is.
struct NewProjectDraft: Equatable {
  var text = ""
  var chosenIcon: String?

  var words: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// What its seal wears: the symbol chosen, else the one the words suggest; `nil` while they suggest none.
  var symbol: String? {
    if let chosenIcon { return chosenIcon }
    let inferred = ProjectIcon.inferred(from: text)
    return inferred == ProjectIcon.fallback ? nil : inferred
  }
}

/// Where a project starts: a large seal over a large field, a little above the middle of the page. Once sent,
/// the seal is gone to the project bar and the field settles at the foot of the page.
struct NewProjectPage: View {
  @Binding var draft: NewProjectDraft
  /// Whether the words are on their way; the field then settles where the project's own field is.
  let sent: Bool
  let attach: () -> Void
  let send: () -> Void
  /// Where the large seal is, for it to fly from once sent.
  let sealFrame: (CGRect) -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var picking = false
  @State private var example = 0

  var body: some View {
    VStack(spacing: 38) {
      if !sent {
        Button {
          picking.toggle()
        } label: {
          HeroSeal(symbol: draft.symbol)
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .disabled(!changesAllowed)
        .popover(isPresented: $picking, arrowEdge: .bottom) {
          ProjectIconPicker(selected: draft.symbol ?? ProjectIcon.fallback) { icon in
            draft.chosenIcon = icon
            picking = false
          }
        }
        .onGeometryChange(for: CGRect.self) {
          $0.frame(in: .named(CompanionPage.space))
        } action: {
          sealFrame($0)
        }
        .transition(.identity)
      }
      StartField(draft: $draft, sent: sent, example: example, attach: attach, send: send)
    }
    .frame(maxWidth: 760)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sent ? .bottom : .center)
    .padding(.bottom, sent ? Spacing.s : Size.newProjectLift)
    .animation(reduceMotion ? nil : Self.settle, value: sent)
    .task(id: sent) {
      guard !sent, !reduceMotion else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.stay)
        if Task.isCancelled { return }
        if draft.text.isEmpty { withAnimation(Motion.swap) { example += 1 } }
      }
    }
  }

  /// How the field settles at the foot of the page once sent.
  static let settle = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.8)
  /// How long each example stays before the next rises in.
  static let stay = Duration.seconds(3)

  static let examples: [LocalizedStringResource] = [
    .loci("projects.exampleFunds"), .loci("projects.exampleTrip"), .loci("projects.exampleInterview"),
    .loci("projects.exampleBook"), .loci("projects.exampleLearn"),
  ]
}

/// The large seal over a new project's field: a dashed blank that floats while nothing suggests a symbol, a
/// solid one wearing the symbol once something does.
struct HeroSeal: View {
  let symbol: String?
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Size.sealLarge * 0.29, style: .continuous)
    ZStack {
      if let symbol {
        shape.fill(Palette.surface)
          .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
          .shadow(color: Palette.liftShadow.opacity(0.5), radius: 15, y: 10)
        Image(systemName: symbol)
          .symbolRenderingMode(.monochrome)
          .font(.system(size: 32, weight: .regular))
          .foregroundStyle(Palette.ink)
          .id(symbol)
          .transition(reduceMotion ? .identity : .scale(scale: 0.5).combined(with: .opacity))
      } else {
        shape.strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
          .background(shape.fill(hovering ? Palette.fill : .clear))
      }
    }
    .frame(width: Size.sealLarge, height: Size.sealLarge)
    .contentShape(shape)
    .onHover { hovering = $0 }
    .phaseAnimator(symbol == nil && !reduceMotion ? [0, -4] : [0]) { seal, rise in
      seal.offset(y: rise)
    } animation: { _ in
      .easeInOut(duration: 1.8)
    }
    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6), value: symbol)
  }
}

/// The large field a project starts from: examples rising in while it is empty, then the words; `+` and send
/// at its foot.
private struct StartField: View {
  @Binding var draft: NewProjectDraft
  let sent: Bool
  let example: Int
  let attach: () -> Void
  let send: () -> Void
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var selection: TextSelection?
  @FocusState private var focused: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: sent ? Size.composerHeight / 2 : 28, style: .continuous)
    let lit = !sent
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topLeading) {
        if draft.text.isEmpty, !sent {
          RollingLine(words: NewProjectPage.examples[example % NewProjectPage.examples.count], index: example, size: 17)
            .allowsHitTesting(false)
        }
        TextField("", text: $draft.text, selection: $selection, axis: .vertical)
          .textFieldStyle(.plain)
          .font(.system(size: sent ? 15 : 17))
          .lineSpacing(4)
          .lineLimit(sent ? 1...1 : 1...6)
          .focused($focused)
          .disabled(!changesAllowed || sent)
          .onSubmit(submit)
          .onKeyPress(.return, phases: .down) { press in
            switch ComposerKey(press.modifiers) {
            case .newLine:
              (draft.text, selection) = ComposerKey.newLine(in: draft.text, at: selection)
              return .handled
            case .send:
              submit()
              return .handled
            case .field:
              return .ignored
            }
          }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
      HStack(spacing: Spacing.xs) {
        Spacer()
        AttachButton(attach: attach)
        RoundButton(symbol: Symbols.send, glyphSize: 13, label: .loci("projects.start"), action: submit)
          .disabled(draft.words.isEmpty || !changesAllowed || sent)
      }
    }
    .padding(EdgeInsets(top: sent ? 14 : 18, leading: 24, bottom: sent ? 8 : 12, trailing: sent ? 8 : 12))
    .frame(height: sent ? Size.composerHeight : 150)
    .background(shape.fill(Palette.surface))
    .overlay(shape.strokeBorder(lit ? Palette.accent : Palette.lineStrong, lineWidth: 1))
    .background(shape.stroke(lit ? Palette.glow : .clear, lineWidth: 8))
    .shadow(color: Palette.liftShadow.opacity(0.18), radius: 14, y: 12)
    .opacity(sent ? 0 : 1)
    .onAppear { focused = true }
  }

  private func submit() {
    guard !sent, changesAllowed, !draft.words.isEmpty else { return }
    send()
  }
}
