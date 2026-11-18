import LociModel
import SwiftUI

/// The conversation with a mentor, sending through the host. A passage put in `draft` is asked about with
/// the next message; `revealPassage` shows a quoted passage where it was read.
struct ConversationScreen: View {
  @Environment(\.host) private var host
  let mentor: Mentor
  let conversation: Conversation?
  @Binding var draft: PassageDraft?
  let revealPassage: @MainActor (Locator) -> Void

  init(
    mentor: Mentor, conversation: Conversation?, draft: Binding<PassageDraft?>,
    revealPassage: @escaping @MainActor (Locator) -> Void
  ) {
    self.mentor = mentor
    self.conversation = conversation
    _draft = draft
    self.revealPassage = revealPassage
  }

  var body: some View {
    ConversationView(
      mentor: mentor, conversation: conversation, draft: $draft, revealPassage: revealPassage,
      send: { (text: String, passage: Passage?) async throws(HostError) -> Done in
        try await host.run(SendMessage(mentor: mentor.id, text: text, passage: passage))
      },
      stop: { _ = try? await host.run(StopTurn(mentor: mentor.id)) },
      startOver: { () async throws(HostError) -> Done in try await host.run(StartOver(mentor: mentor.id)) })
  }
}

/// Everything said with one mentor, newest at the bottom, with the input field floating over its foot.
///
/// Each entry is its own view keyed by its first message, so a reply that grows while it streams redraws
/// only itself.
struct ConversationView: View {
  let mentor: Mentor
  let conversation: Conversation?
  @Binding var draft: PassageDraft?
  let revealPassage: @MainActor (Locator) -> Void
  let send: (String, Passage?) async throws(HostError) -> Done
  let stop: () async -> Void
  /// What `/new` in the composer does; without it, `/new` is sent like any message.
  var startOver: (() async throws(HostError) -> Done)?
  /// On a conversation several mentors took part in, who answered each reply; it is named above it.
  var answeredBy: ((Message) -> Mentor?)?
  /// The day and time over the first message of each sitting, and a short conversation reads from the top.
  var showsDays = false
  /// The composer keeps to the field and send, without the agent's menus.
  var plainComposer = false
  /// Starts keeping the newest line in view.
  @State var follow = Following()
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var scrolling = false
  @State private var pointedAnswer: EntityID?

  var body: some View {
    ScrollView {
      let answers = ConversationEntry.answers(entries)
      LazyVStack(alignment: .leading, spacing: Self.spacing) {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
          if showsDays, let day = Sitting.start(of: entry, after: index > 0 ? entries[index - 1] : nil) {
            Sitting.label(day, now: Date())
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(Palette.inkFaint)
              .frame(maxWidth: .infinity)
          }
          if let answeredBy, case .reply(let message, _, _) = entry, let mentor = answeredBy(message),
            Self.startsAnswer(entries, at: index)
          {
            HStack(spacing: 7) {
              Avatar(mentor: mentor, size: Size.avatarTiny)
              Text(verbatim: mentor.name)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.inkMuted)
            .padding(.bottom, -6)
          }
          row(entry, answer: answers[entry.id]).transition(.opacity.combined(with: .offset(y: 10)))
        }
        if waiting { StepsCard.waiting.transition(.opacity.combined(with: .offset(y: 10))) }
      }
      .animation(Motion.rise, value: entries.count)
      .padding(.horizontal, 18)
      .padding(.top, 6)
      .padding(.bottom, Spacing.m)
    }
    .defaultScrollAnchor(showsDays ? .top : .bottom, for: .alignment)
    .defaultScrollAnchor(.bottom, for: .initialOffset)
    .scrollPosition($position)
    .onScrollPhaseChange { _, phase in
      scrolling = phase == .tracking || phase == .interacting || phase == .decelerating
    }
    .onScrollGeometryChange(for: CGFloat.self, of: Following.distanceFromEnd) { _, distance in
      if scrolling { follow.scrolled(to: distance) }
    }
    .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, _ in
      if follow.isOn && !scrolling { position.scrollTo(edge: .bottom) }
    }
    .onChange(of: questions) {
      follow.asked()
      withAnimation(Motion.standard) { position.scrollTo(edge: .bottom) }
    }
    .scrollIndicators(.never)
    .mask(
      LinearGradient(
        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03)], startPoint: .top,
        endPoint: .bottom)
    )
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Composer(
        mentor: mentor, context: conversation?.context, busy: conversation?.turn != nil, draft: $draft, send: send,
        stop: stop, startOver: startOver, plain: plainComposer
      )
      .overlay(alignment: .top) {
        if follow.offersLatest {
          LatestButton(busy: conversation?.turn != nil) {
            follow.returned()
            withAnimation(Motion.standard) { position.scrollTo(edge: .bottom) }
          }
          .offset(y: -(LatestButton.size + Spacing.s))
          .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
      }
      .animation(Motion.quick, value: follow.offersLatest)
      .padding(.horizontal, Spacing.s)
      .padding(.bottom, Spacing.s)
      .padding(.top, Spacing.m)
      .background(
        LinearGradient(
          stops: [.init(color: Palette.well.opacity(0), location: 0), .init(color: Palette.well, location: 0.45)],
          startPoint: .top, endPoint: .bottom))
    }
    .background(Palette.well)
  }

  private static let spacing: CGFloat = 14

  /// The pointer came over an answer's last reply or its actions, or left them.
  private func point(_ inside: Bool, at answer: EntityID) {
    if inside {
      pointedAnswer = answer
    } else if pointedAnswer == answer {
      pointedAnswer = nil
    }
  }

  /// Questions the person has asked; one more means the conversation goes to its end to show the answer.
  private var questions: Int {
    entries.count { if case .asked = $0 { true } else { false } }
  }

  private var entries: [ConversationEntry] {
    ConversationEntry.layout(
      (conversation?.messages ?? []) + (conversation?.turn?.messages ?? []), live: conversation?.turn != nil)
  }

  /// The first reply after a question, where the name of who answered goes.
  private static func startsAnswer(_ entries: [ConversationEntry], at index: Int) -> Bool {
    for earlier in entries[..<index].reversed() {
      switch earlier {
      case .reply: return false
      case .asked: return true
      case .aside, .steps, .saved: continue
      }
    }
    return true
  }

  /// The mentor is at work but has shown nothing of it yet.
  private var waiting: Bool {
    guard let turn = conversation?.turn else { return false }
    if case .prompt = turn.messages.last?.body { return true }
    return false
  }

  @ViewBuilder private func row(_ entry: ConversationEntry, answer: String?) -> some View {
    switch entry {
    case .asked(_, let prompt):
      AskedMessage(prompt: prompt, revealPassage: revealPassage)
    case .aside(let message):
      AsideLine(message: message)
    case .steps(let steps):
      StepsCard(steps: steps)
    case .reply(let message, let text, let streaming):
      ReplyText(text: text, streaming: streaming, spacing: Self.spacing)
        .padding(.horizontal, 2)
        .onHover { if answer != nil { point($0, at: message.id) } }
      if let answer {
        AnswerActions(text: answer, shown: pointedAnswer == message.id)
          .padding(.top, Spacing.xxs - Self.spacing)
          .onHover { point($0, at: message.id) }
      }
    case .saved:
      SavedChip()
    }
  }
}

/// Messages more than an hour apart belong to different sittings, each headed by when it began.
enum Sitting {
  static let gap: TimeInterval = 3600

  static func start(of entry: ConversationEntry, after earlier: ConversationEntry?) -> Date? {
    let at = entry.at.date
    guard let earlier else { return at }
    return at.timeIntervalSince(earlier.at.date) > gap ? at : nil
  }

  /// `今天 21:04`, `昨天 22:30`, or the date for anything older.
  static func label(_ date: Date, now: Date, calendar: Calendar = .current) -> Text {
    let time = Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    if calendar.isDate(date, inSameDayAs: now) {
      return Text(joining: Text(.loci("day.today")), Text(verbatim: " "), time)
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday)
    {
      return Text(joining: Text(.loci("day.yesterday")), Text(verbatim: " "), time)
    }
    return Text(joining: Text(date, format: .dateTime.month().day()), Text(verbatim: " "), time)
  }
}

extension ConversationEntry {
  /// When the message it begins with was said.
  var at: Timestamp {
    switch self {
    case .asked(let message, _), .aside(let message), .reply(let message, _, _), .saved(let message, _): message.at
    case .steps(let steps): steps[0].at
    }
  }
}
