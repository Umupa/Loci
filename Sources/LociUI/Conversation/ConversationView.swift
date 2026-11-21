import LociModel
import SwiftUI

/// A conversation with Loci, sending through the host. A passage put in `draft` is asked about with the
/// next message; `revealPassage` shows a quoted passage where it was read.
struct ConversationScreen: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  let ref: ConversationRef
  @Binding var draft: PassageDraft?
  var revealPassage: @MainActor (Locator) -> Void = { _ in }
  var attach: (() -> Void)?
  var focusRequest = 0
  @State private var conversation: Feed<Conversation>?

  var body: some View {
    ConversationView(
      conversation: conversation?.value, draft: $draft,
      revealPassage: { openPage.follow($0, in: ref, reveal: revealPassage) },
      send: { (text: String, passage: Passage?) async throws(HostError) -> Done in
        try await host.run(SendMessage(to: ref, text: text, passage: passage))
      },
      stop: { _ = try? await host.run(StopTurn(in: ref)) },
      startOver: { () async throws(HostError) -> Done in try await host.run(StartOver(in: ref)) },
      scale: ref == .main ? .main : .companion, attach: attach, focusRequest: focusRequest
    )
    .id(ref)
    .environment(
      \.openURL,
      OpenURLAction { url in
        openPage.follow(url, in: ref, reveal: revealPassage)
      }
    )
    .subscribing(OneConversation(ref), into: $conversation)
    .showingDocuments()
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
  /// What adding a file from the composer's plus menu does.
  var attach: (() -> Void)?
  /// Changes each time the composer should take the keyboard.
  var focusRequest = 0
  /// How long the reply being written waits, with no tool after it, before it shows.
  var replyHold = Motion.replyHold
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns
  /// Starts keeping the newest line in view.
  @State var follow = Following()
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var scrolling = false
  @State private var pointedAnswer: EntityID?
  @State private var settled = Remembered(TalkRow.settled)
  /// How many of the earliest rows are not drawn; `nil` until the conversation arrives.
  @State private var hidden: Int?
  @State private var composing = false
  /// When a reply held back last came due, so the conversation is drawn again to show it.
  @State private var cameDue = Date.distantPast
  @State private var cover = ConversationCover()

  var body: some View {
    let said = said
    let now = standIns?.conversationAt ?? max(cameDue, .now)
    let live = TalkRow.live(conversation?.turn, hold: ReplyHold(now: now, wait: replyHold))
    let start = min(hidden ?? RowWindow.latest(in: said), said.count)
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: Self.gap) {
        ForEach(TalkRow.offered(Array(said[start...]) + live, composing: composing)) { row in
          view(of: row).arriving()
        }
      }
      .animatingArrivals(said.count(where: \.arrives) + live.count(where: \.arrives))
      .frame(maxWidth: scale == .main ? Size.talkColumn : .infinity)
      .padding(.horizontal, scale == .main ? 28 : Spacing.m)
      .padding(.top, scale == .main ? 40 : 0)
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
    .task(id: ReplyHold.due(conversation?.turn, wait: replyHold)) {
      guard let due = ReplyHold.due(conversation?.turn, wait: replyHold), standIns == nil else { return }
      try? await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
      if !Task.isCancelled { cameDue = .now }
    }
    .onChange(of: said.isEmpty, initial: true) {
      if hidden == nil, !said.isEmpty { hidden = RowWindow.latest(in: said) }
    }
    .onChange(of: questions) {
      follow.asked()
      withAnimation(reduceMotion ? nil : Motion.standard) { position.scrollTo(edge: .bottom) }
    }
    .scrollIndicators(.never)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Composer(
        busy: conversation?.turn != nil, draft: $draft, send: send, stop: stop, startOver: startOver,
        style: scale == .main ? .talk : .companion, attach: scale == .main ? attach : nil, focusRequest: focusRequest,
        composing: $composing
      )
      .overlay(alignment: .top) {
        if follow.offersLatest {
          LatestButton {
            follow.returned()
            withAnimation(reduceMotion ? nil : Motion.standard) { position.scrollTo(edge: .bottom) }
          }
          .offset(y: -(LatestButton.size + Spacing.s))
          .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.8)))
        }
      }
      .animation(reduceMotion ? nil : Motion.quick, value: follow.offersLatest)
      .frame(maxWidth: scale == .main ? Size.talkColumn : .infinity)
      .padding(.horizontal, scale == .main ? 28 : 14)
      .padding(.bottom, scale == .main ? 24 : 14)
      .padding(.top, Spacing.l)
      .background {
        LinearGradient(
          stops: [.init(color: .clear, location: 0), .init(color: Palette.canvas, location: 0.7)], startPoint: .top,
          endPoint: .bottom
        )
        .allowsHitTesting(false)
      }
      .offlineLineInstead(ruled: scale != .main)
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .global)
      } action: {
        cover.area = $0
      }
    }
    .environment(\.conversationCover, cover)
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

  /// The room between one message and the next.
  static let gap: CGFloat = 10

  @ViewBuilder private func view(of row: TalkRow) -> some View {
    switch row.kind {
    case .day(let day):
      DayDivider(label: Sitting.label(day, now: Date()))
    case .asked(let prompt):
      BubbleRow(speaker: .person, scale: scale) { AskedMessage(prompt: prompt, revealPassage: revealPassage) }
    case .said(let words, let answer):
      BubbleRow(
        speaker: .loci, scale: scale,
        words: {
          VStack(alignment: .leading, spacing: 0) { ReplyText(text: words, streaming: false, size: scale.fontSize) }
        },
        beside: {
          if let answer { AnswerActions(text: answer, shown: pointedAnswer == row.reply) }
        }
      )
      .onHover { pointedAnswer = $0 ? row.reply : nil }
    case .doing(let doing):
      DoingLine(doing: doing, size: scale.fontSize)
    case .replies(let replies):
      QuickReplyChips(replies: replies, size: scale.fontSize) { reply in
        Task { _ = try? await send(reply, nil) }
      }
    case .ended(let ending):
      BubbleRow(speaker: .loci, scale: scale) { EndedTurn(ending: ending) }
    case .startedOver:
      StartedOverLine().padding(.vertical, 10)
    case .saved:
      SavedChip()
    case .finished(let item, let at):
      FinishedCard(item: item, at: at)
    case .task(let item, let job):
      SavingCard(item: item, job: job)
    case .cards(let items):
      LibraryCards(items: items) { SavedItemByline($0).text }
    case .savedItems(let items):
      SavedItemsCard(items: items).padding(.vertical, 6)
    case .document(let document):
      DocumentCard(id: row.id, document: document)
    case .links(let links):
      LinkCards(links: links)
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
    case .savedItems(let messages): messages[0].at
    case .event(let event): event.at
    }
  }
}
