import LociModel
import SwiftUI

/// What the person does in the builder, handed to whoever keeps the course.
struct BuilderActions {
  var answer: (CourseQuestion, CourseAnswer) -> Void = { _, _ in }
  var goOn: () -> Void = {}
  var collapse: () -> Void = {}
  var strike: (SourceShown) -> Void = { _ in }
  var addSource: (URL) -> Void = { _ in }
  var openSource: (URL) -> Void = { _ in }
}

/// Moving parts of the builder caught at a fixed moment, for a snapshot.
struct BuilderMoment {
  /// An answer on its way to a line of the title page, and how far along.
  var flight: (answer: Int, line: Int, progress: Double)?
  var ink: (line: Int, progress: Double)?
  var landing: (id: EntityID, progress: Double)?
  var pointedSource: EntityID?
  var turning: (leaf: Leaf, progress: Double)?
  var invitation: Double?
}

/// The card a course is built in: the stages along the top, the conversation on the left, the desk on the
/// right — the title page, then the sources, then the open book — and the next step at the foot. While Loci
/// works, amber light runs round its edge and glows faintly inside it. Loci's open question, at the end of the
/// conversation, is answered through it.
struct CourseBuilder<Chat: View>: View {
  let shown: BuilderShown
  let actions: BuilderActions
  /// The course was started just now, so its title page inks in from blank.
  var newlyStarted = false
  var moment = BuilderMoment()
  @ViewBuilder let chat: () -> Chat
  @State private var flights: [Flight] = []
  @State private var ends: [FlightEnd: CGRect] = [:]
  @State private var chosen: Set<Int> = []

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.builder, style: .continuous)
    VStack(spacing: 0) {
      head
      HStack(spacing: 0) {
        chat()
          .environment(\.answering, Answering(chosen: chosen, pick: pick, sayElse: sayElse))
          .frame(width: Size.builderChat)
          .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: Size.hairline) }
        desk
      }
      BuilderFoot(
        stage: shown.stage, canGoOn: shown.canGoOn, invitation: moment.invitation, later: actions.collapse,
        goOn: actions.goOn)
    }
    .background(
      shape.fill(
        Palette.builderFace.shadow(.inner(color: Palette.Glow.amber.opacity(shown.working ? 0.16 : 0), radius: 40)))
    )
    .animation(.easeInOut(duration: 0.8), value: shown.working)
    .overlay { shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline) }
    .clipShape(shape)
    .amberGlow(shown.working, corner: Radius.builder)
    .shadow(color: Palette.warmShadow.opacity(0.4), radius: 50, y: 40)
    .coordinateSpace(.named(BuilderSpace.name))
    .backgroundPreferenceValue(FlightEnds.self) { anchors in
      GeometryReader { proxy in
        let frames = anchors.mapValues { proxy[$0] }
        Color.clear.onChange(of: frames, initial: true) { _, now in ends = now }
      }
    }
    .overlay { flying }
    .onChange(of: shown.question) { chosen = [] }
  }

  private var head: some View {
    CourseStageRuler(stage: shown.stage, fraction: shown.fraction)
      .frame(width: 420)
      .frame(maxWidth: .infinity)
      .frame(height: Size.builderHead)
      .overlay(alignment: .trailing) {
        Button(action: actions.collapse) {
          Image(systemName: Symbols.collapseBuilder)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.inkMuted)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Palette.fill))
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(AnswerPress(scale: 0.92))
        .padding(.trailing, 14)
        .accessibilityLabel(Text(.loci("course.collapse")))
      }
  }

  private var desk: some View {
    ZStack {
      scene(.goal) {
        TitlePage(
          title: shown.title, goal: shown.goal, sealed: shown.sealed, held: moment.ink, newlyStarted: newlyStarted)
      }
      scene(.sources) {
        SourceDesk(
          sources: shown.sources, editable: shown.stage == .sources, landing: moment.landing,
          pointed: moment.pointedSource, strike: actions.strike, add: actions.addSource,
          open: actions.openSource)
      }
      scene(.writing) {
        OpenBook(
          title: shown.title, subtitle: shown.goal.subtitle, lessons: shown.lessons, leaf: shown.leaf,
          turning: moment.turning)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      Palette.desk.overlay {
        RadialGradient(colors: [Palette.accent.opacity(0.05), .clear], center: .center, startRadius: 0, endRadius: 420)
      }
    }
    .clipped()
  }

  /// One of the desk's three scenes: in focus while its stage is on, drawn back and blurred once past, waiting
  /// a little large and blurred before.
  private func scene(_ stage: CourseStage, @ViewBuilder content: () -> some View) -> some View {
    let on = shown.stage == stage
    return content()
      .opacity(on ? 1 : 0)
      .scaleEffect(on ? 1 : stage.isBefore(shown.stage) ? 0.94 : 1.04)
      .blur(radius: on ? 0 : 7)
      .allowsHitTesting(on)
      .animation(.spring(duration: 0.7, bounce: 0.06), value: shown.stage)
      .accessibilityHidden(!on)
  }

  @ViewBuilder private var flying: some View {
    if let held = moment.flight, let from = ends[.answer(held.answer)], let to = ends[.line(held.line)] {
      FlyingAnswer(
        flight: Flight(from: from, to: to, words: shown.question?.draft.title(of: held.answer) ?? ""),
        progress: held.progress)
    }
    ForEach(flights) { flight in
      LaunchedFlight(flight: flight) { flights.removeAll { $0.id == flight.id } }
    }
  }

  /// Sends the answers chosen, and sends each off to its line of the title page.
  private func pick(_ answers: [Int]) {
    guard chosen.isEmpty, let question = shown.question else { return }
    chosen = Set(answers)
    if question.draft.answering != .reply, let line = shown.goal.line(answering: question.draft),
      let to = ends[.line(line)]
    {
      flights += answers.enumerated().compactMap { order, answer in
        ends[.answer(answer)].map {
          Flight(from: $0, to: to, words: question.draft.title(of: answer), delay: Double(order) * 0.09)
        }
      }
    }
    actions.answer(question, question.draft.multiple ? .options(answers) : .option(answers.first ?? 0))
  }

  /// Answers the open question in the person's own words.
  private func sayElse(_ words: String) {
    guard chosen.isEmpty, let question = shown.question else { return }
    chosen = [-1]
    actions.answer(question, .text(words))
  }

}

/// The builder's own coordinate space, in which an answer's flight is drawn.
enum BuilderSpace {
  static let name = "builder"
}
