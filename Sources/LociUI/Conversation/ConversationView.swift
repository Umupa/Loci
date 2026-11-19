import LociModel
import SwiftUI

/// A conversation with Loci, sending through the host. A passage put in `draft` is asked about with the
/// next message; `revealPassage` shows a quoted passage where it was read.
struct ConversationScreen: View {
  @Environment(\.host) private var host
  let ref: ConversationRef
  @Binding var draft: PassageDraft?
  let revealPassage: @MainActor (Locator) -> Void
  var attach: (() -> Void)?
  var focusRequest = 0
  @State private var conversation: Feed<Conversation>?

  var body: some View {
    ConversationView(
      conversation: conversation?.value, draft: $draft, revealPassage: revealPassage,
      send: { (text: String, passage: Passage?) async throws(HostError) -> Done in
        try await host.run(SendMessage(to: ref, text: text, passage: passage))
      },
      stop: { _ = try? await host.run(StopTurn(in: ref)) },
      startOver: { () async throws(HostError) -> Done in try await host.run(StartOver(in: ref)) },
      scale: ref == .main ? .main : .companion, attach: attach, focusRequest: focusRequest
    )
    .id(ref)
    .subscribing(OneConversation(ref), into: $conversation)
  }
}

/// Everything said with Loci as a chat, newest at the bottom, with the input field floating over its foot.
///
/// Each row is its own view keyed by its message and part, so a reply that grows while it streams redraws
/// only its last bubble. What was said before the running turn is laid out once, not again as the reply
/// grows.
struct ConversationView: View {
  let conversation: Conversation?
  @Binding var draft: PassageDraft?
  let revealPassage: @MainActor (Locator) -> Void
  let send: (String, Passage?) async throws(HostError) -> Done
  let stop: () async -> Void
  /// What `/new` in the composer does; without it, `/new` is sent like any message.
  var startOver: (() async throws(HostError) -> Done)?
  var scale = TalkScale.main
  /// What the composer's plus button does.
  var attach: (() -> Void)?
  /// Changes each time the composer should take the keyboard.
  var focusRequest = 0
  /// Starts keeping the newest line in view.
  @State var follow = Following()
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var scrolling = false
  @State private var pointedAnswer: EntityID?
  @State private var settled = Remembered(TalkRow.settled)
  /// How many of the earliest rows are not drawn; `nil` until the conversation arrives.
  @State private var hidden: Int?

  var body: some View {
    let said = said
    let live = TalkRow.live(conversation?.turn)
    let start = min(hidden ?? RowWindow.latest(in: said), said.count)
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(said[start...] + live) { row in
          view(of: row).arriving()
        }
      }
      .animatingArrivals(said.count(where: \.arrives) + live.count(where: \.arrives))
      .padding(.horizontal, scale == .main ? 28 : Spacing.m)
      .frame(maxWidth: scale == .main ? 640 : .infinity)
      .padding(.top, scale == .main ? Spacing.l : 0)
      .frame(maxWidth: .infinity)
    }
    .defaultScrollAnchor(.top, for: .alignment)
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
    .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top < 1 }) { _, atTop in
      let said = said
      guard atTop, let hidden, hidden > 0, hidden < said.count else { return }
      self.hidden = RowWindow.earlier(than: hidden, in: said)
      position.scrollTo(id: said[hidden].id, anchor: .top)
    }
    .onChange(of: said.isEmpty, initial: true) {
      if hidden == nil, !said.isEmpty { hidden = RowWindow.latest(in: said) }
    }
    .onChange(of: questions) {
      follow.asked()
      withAnimation(Motion.standard) { position.scrollTo(edge: .bottom) }
    }
    .scrollIndicators(.never)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Composer(
        context: conversation?.context, busy: conversation?.turn != nil, draft: $draft, send: send,
        stop: stop, startOver: startOver, style: scale == .main ? .talk : .companion,
        attach: scale == .main ? attach : nil, focusRequest: focusRequest
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
      .frame(maxWidth: scale == .main ? 640 : .infinity)
      .padding(.horizontal, scale == .main ? 28 : 14)
      .padding(.bottom, scale == .main ? 18 : 14)
      .padding(.top, Spacing.l)
      .offlineLineInstead(ruled: scale != .main)
    }
    .background(Palette.canvas)
  }

  private var said: [TalkRow] {
    settled(SaidSoFar(conversation?.entries ?? [], turn: conversation?.turn))
  }

  /// Questions the person has asked; one more means the conversation goes to its end to show the answer.
  private var questions: Int {
    let said = (conversation?.entries ?? []).count {
      if case .message(let message) = $0, case .prompt = message.body { true } else { false }
    }
    return said + (conversation?.turn == nil ? 0 : 1)
  }

  @ViewBuilder private func view(of row: TalkRow) -> some View {
    switch row.kind {
    case .day(let day):
      DayDivider(label: Sitting.label(day, now: Date()))
    case .asked(let prompt):
      bubble(row) { AskedMessage(prompt: prompt, revealPassage: revealPassage) }
    case .said(let words, let answer):
      BubbleRow(
        speaker: .loci, position: row.position ?? .alone, turn: row.turn, scale: scale,
        words: {
          VStack(alignment: .leading, spacing: 0) { ReplyText(text: words, streaming: false, size: scale.fontSize) }
        },
        beside: {
          if let answer { AnswerActions(text: answer, shown: pointedAnswer == row.reply) }
        }
      )
      .onHover { pointedAnswer = $0 ? row.reply : nil }
    case .typing:
      bubble(row) { TypingDots() }
    case .steps(let steps):
      StepsCard(steps: steps).padding(.leading, scale.indent).padding(.vertical, 6)
    case .aside(let message):
      AsideLine(message: message).padding(.vertical, 10)
    case .saved:
      SavedChip().padding(.leading, scale.indent).padding(.vertical, 6)
    case .finished(let item, let at):
      EventPill(
        words: Text(joining: Text(.loci("talk.finished")), Text(verbatim: " · " + item.title)),
        time: Text(at, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
      ) {
        Cover(item: item, corner: 0, symbolSize: 11)
      }
    case .task(let item, let job):
      SavingCard(item: item, job: job, indent: scale.indent)
    case .cards(let items):
      ItemCardRow(indent: scale.indent) {
        ForEach(items, id: \.id) { item in SavedItemCard(item: item) }
      }
    }
  }

  private func bubble(_ row: TalkRow, @ViewBuilder words: () -> some View) -> some View {
    BubbleRow(
      speaker: row.speaker ?? .loci, position: row.position ?? .alone, turn: row.turn, scale: scale, words: words)
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
    case .event(let event): event.at
    }
  }
}
