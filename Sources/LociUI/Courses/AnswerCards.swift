import LociModel
import SwiftUI

/// Loci's open question at the end of a course's conversation: the question in Loci's bubble, and under it the
/// answers it wrote, answered through the builder around it.
struct QuestionTail: View {
  @Environment(\.answering) private var answering
  let question: CourseQuestion

  var body: some View {
    VStack(alignment: .leading, spacing: Size.messageGap) {
      BubbleRow(speaker: .loci, scale: .companion) { Text(verbatim: question.draft.question) }
      AnswerCards(
        question: question.draft, chosen: answering?.chosen ?? [], pick: { answering?.pick($0) },
        sayElse: { answering?.sayElse($0) }
      )
      .changesData()
      .padding(.bottom, Spacing.xs)
    }
    .id(question.id)
    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
  }
}

/// How the builder takes an answer: the answers already chosen, choosing some, and saying something else.
struct Answering {
  let chosen: Set<Int>
  let pick: ([Int]) -> Void
  let sayElse: (String) -> Void
}

extension EnvironmentValues {
  /// Set by the builder for the question at the end of its conversation.
  @Entry var answering: Answering?
}

/// The answers Loci wrote for its question, under it in the conversation. One to pick is a stack of cards, the
/// recommended one ringed in amber, and last a card to say something else; several that can hold at once are
/// boxes to tick and a button to go on; a reply to Loci's account is a row of capsules.
struct AnswerCards: View {
  let question: CourseQuestion.Draft
  /// The answers already chosen, which the others fade back from as they leave.
  var chosen: Set<Int> = []
  let pick: ([Int]) -> Void
  let sayElse: (String) -> Void
  @State private var ticked: Set<Int> = []
  @State private var typing = false
  @State private var words = ""
  @FocusState private var focused: Bool

  var body: some View {
    switch question.answering {
    case .one: cards
    case .many: toggles
    case .reply: replies
    }
  }

  private var cards: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(question.options.enumerated()), id: \.offset) { index, answer in
        Button {
          pick([index])
        } label: {
          AnswerCard(answer: answer, recommended: index == 0)
        }
        .buttonStyle(AnswerPress())
        .anchorPreference(key: FlightEnds.self, value: .bounds) { [.answer(index): $0] }
        .opacity(chosen.isEmpty || chosen.contains(index) ? 1 : 0.25)
        .risingIn(order: index)
      }
      somethingElse.risingIn(order: question.options.count)
    }
    .padding(.leading, 14)
  }

  @ViewBuilder private var somethingElse: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.answer, style: .continuous)
    HStack(spacing: 11) {
      Image(systemName: Symbols.pencil).font(.system(size: 13)).frame(width: 16)
      if typing {
        TextField(text: $words, prompt: Text(.loci("course.answerElse"))) { Text(.loci("course.answerElse")) }
          .textFieldStyle(.plain)
          .focused($focused)
          .onSubmit {
            let said = words.trimmingCharacters(in: .whitespacesAndNewlines)
            if !said.isEmpty { sayElse(said) }
          }
          .foregroundStyle(Palette.ink)
      } else {
        Text(.loci("course.answerElse"))
        Spacer(minLength: 0)
      }
    }
    .font(.system(size: 14))
    .foregroundStyle(Palette.inkMuted)
    .padding(.vertical, 9).padding(.leading, 12).padding(.trailing, 14)
    .overlay { shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline) }
    .contentShape(shape)
    .onTapGesture {
      typing = true
      focused = true
    }
    .opacity(chosen.isEmpty ? 1 : 0.25)
  }

  private var toggles: some View {
    VStack(alignment: .trailing, spacing: Spacing.xs) {
      FlowRow(spacing: 6) {
        ForEach(Array(question.options.enumerated()), id: \.offset) { index, answer in
          Button {
            if ticked.contains(index) { ticked.remove(index) } else { ticked.insert(index) }
          } label: {
            TickChip(title: answer.title, ticked: ticked.contains(index))
          }
          .buttonStyle(AnswerPress(scale: 0.95))
          .anchorPreference(key: FlightEnds.self, value: .bounds) { [.answer(index): $0] }
          .risingIn(order: index)
        }
      }
      Button {
        pick(ticked.sorted())
      } label: {
        Text(.loci("course.answerContinue"))
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(Palette.onAccent)
          .padding(.horizontal, 18).padding(.vertical, 9)
          .background(Capsule().fill(Palette.accent))
      }
      .buttonStyle(AnswerPress(scale: 0.95))
      .disabled(ticked.isEmpty)
      .opacity(ticked.isEmpty ? 0.45 : 1)
      .animation(Motion.quick, value: ticked.isEmpty)
    }
    .padding(.leading, 14)
    .opacity(chosen.isEmpty ? 1 : 0.25)
  }

  private var replies: some View {
    HStack(spacing: 7) {
      ForEach(question.options.indices, id: \.self) { index in
        Button {
          pick([index])
        } label: {
          HStack(spacing: 7) {
            if index == 0 { Circle().fill(Palette.accent).frame(width: 5, height: 5) }
            Text(index == 0 ? .loci("course.confirmGoal") : .loci("course.reviseGoal"))
          }
          .font(.system(size: 14))
          .foregroundStyle(Palette.ink)
          .padding(.horizontal, 15).padding(.vertical, 10)
          .overlay {
            Capsule().strokeBorder(
              index == 0 ? Palette.accent.opacity(0.55) : Palette.inkFaint.opacity(0.6),
              lineWidth: index == 0 ? 1 : Size.hairline)
          }
          .contentShape(Capsule())
        }
        .buttonStyle(AnswerPress(scale: 0.95))
        .risingIn(order: index)
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
  }
}

/// One answer to pick: a round mark, a line of title and a line saying what it means.
private struct AnswerCard: View {
  let answer: CourseQuestion.Option
  let recommended: Bool
  @State private var hovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.answer, style: .continuous)
    HStack(alignment: .top, spacing: 11) {
      Circle()
        .strokeBorder(recommended ? Palette.accent : Palette.inkFaint, lineWidth: 1.2)
        .overlay { if recommended { Circle().fill(Palette.accent.opacity(0.55)).padding(4.5) } }
        .frame(width: 16, height: 16)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: answer.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
        if !answer.detail.isEmpty {
          Text(verbatim: answer.detail).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted)
        }
      }
      .lineSpacing(2)
      .multilineTextAlignment(.leading)
      Spacer(minLength: 0)
    }
    .padding(.top, 11).padding(.bottom, 12).padding(.leading, 12).padding(.trailing, 14)
    .background(shape.fill(hovering ? Palette.fillStrong : Palette.bubble))
    .overlay {
      shape.strokeBorder(
        recommended ? Palette.accent.opacity(0.6) : Palette.lineStrong, lineWidth: recommended ? 1 : Size.hairline)
    }
    .contentShape(shape)
    .offset(x: hovering ? -2 : 0)
    .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
    .onHover { hovering = $0 }
  }
}

/// A box to tick in a capsule; ticked, it fills amber and the capsule takes an amber wash.
private struct TickChip: View {
  let title: String
  let ticked: Bool

  var body: some View {
    HStack(spacing: 7) {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(ticked ? Palette.accent : .clear)
        .overlay {
          if ticked {
            Image(systemName: Symbols.done).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Palette.onAccent)
          } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.inkFaint, lineWidth: 1.2)
          }
        }
        .frame(width: 13, height: 13)
      Text(verbatim: title)
    }
    .font(.system(size: 14))
    .foregroundStyle(Palette.ink)
    .padding(.horizontal, 14).padding(.vertical, 9)
    .background(Capsule().fill(ticked ? Palette.tint : Palette.bubble))
    .overlay {
      Capsule().strokeBorder(
        ticked ? Palette.accent.opacity(0.55) : Palette.lineStrong, lineWidth: ticked ? 1 : Size.hairline)
    }
    .contentShape(Capsule())
    .animation(Motion.quick, value: ticked)
  }
}

/// Pressing an answer pushes it in; it springs back on release.
struct AnswerPress: ButtonStyle {
  var scale = 0.98

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? scale : 1)
      .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
  }
}

/// Lays its children out in rows from the left, wrapping to the next row when one is full.
struct FlowRow: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? 300, subviews: subviews)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.members {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private func arrange(width: CGFloat, subviews: Subviews) -> [(members: [Int], width: CGFloat, height: CGFloat)] {
    var rows: [(members: [Int], width: CGFloat, height: CGFloat)] = []
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      if let last = rows.last, last.width + spacing + size.width <= width {
        rows[rows.count - 1].members.append(index)
        rows[rows.count - 1].width += spacing + size.width
        rows[rows.count - 1].height = max(last.height, size.height)
      } else {
        rows.append(([index], size.width, size.height))
      }
    }
    return rows
  }
}

extension View {
  /// Rises into place a moment after the one before it.
  func risingIn(order: Int) -> some View {
    modifier(RisingIn(delay: Double(order) * 0.07))
  }
}

private struct RisingIn: ViewModifier {
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns
  let delay: Double
  @State private var shown = false

  func body(content: Content) -> some View {
    let still = reduceMotion || standIns != nil
    content
      .opacity(still || shown ? 1 : 0)
      .offset(y: still || shown ? 0 : Motion.riseDistance)
      .onAppear { withAnimation(Motion.arrive.delay(delay)) { shown = true } }
  }
}
