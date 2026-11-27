import LociModel
import SwiftUI

/// A conversation with Loci, sending through the host. A passage put in `draft` is asked about with the
/// next message; `revealPassage` shows a quoted passage where it was read. `tail` follows the last message.
struct ConversationScreen<Tail: View>: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  @Environment(\.documents) private var documents
  @Environment(\.homeSwitch) private var homeSwitch
  let ref: ConversationRef
  @Binding var draft: PassageDraft?
  var revealPassage: @MainActor (Locator) -> Void = { _ in }
  var attach: (() -> Void)?
  var focusRequest = 0
  var panelRequest = PanelRequest()
  var visit: ConversationVisit?
  /// The lesson being read beside a course's conversation, which what is sent is about.
  var lesson: Lesson.ID?
  var courseLessons: [Lesson] = []
  @ViewBuilder var tail: () -> Tail
  @State private var conversation: Feed<Conversation>?

  var body: some View {
    Group {
      if documents == nil {
        view.showingDocuments()
      } else {
        view
      }
    }
    .id(ref)
    .modifier(FollowingLinks(ref: ref, revealPassage: revealPassage))
    .subscribing(OneConversation(ref), into: $conversation)
    .onChange(of: conversation?.value != nil, initial: true) {
      if conversation?.value != nil { homeSwitch?.arrived(.conversation, in: ref.home) }
    }
  }

  private var view: some View {
    ConversationView(
      conversation: conversation?.value, ref: ref, draft: $draft,
      revealPassage: { openPage.follow($0, in: ref, reveal: revealPassage) },
      send: { (text: String, passage: Passage?) async throws(HostError) -> Done in
        try await host.run(SendMessage(to: ref, text: text, passage: passage, lesson: lesson))
      },
      stop: { _ = try? await host.run(StopTurn(in: ref)) },
      startOver: { () async throws(HostError) -> Done in try await host.run(StartOver(in: ref)) },
      scale: ref == ref.home.conversation ? .main : .companion, attach: attach, focusRequest: focusRequest,
      panelRequest: panelRequest, visit: visit,
      courseLessons: courseLessons, tail: tail
    )
  }
}

/// A web link clicked in a conversation opens over it; a `loci://` place opens where it was read.
private struct FollowingLinks: ViewModifier {
  @Environment(\.openPage) private var openPage
  @Environment(\.peekLink) private var peekLink
  @Environment(\.openPlace) private var openPlace
  let ref: ConversationRef
  let revealPassage: @MainActor (Locator) -> Void

  func body(content: Content) -> some View {
    content.environment(
      \.openURL,
      OpenURLAction { url in
        if let connector = ConnectorID(link: url) {
          openPlace(.connector(connector))
          return .handled
        }
        if url.isWebLink, let peekLink {
          peekLink(url)
          return .handled
        }
        return openPage.follow(url, in: ref, reveal: revealPassage)
      })
  }
}

extension ConversationScreen where Tail == EmptyView {
  init(
    ref: ConversationRef, draft: Binding<PassageDraft?>,
    revealPassage: @escaping @MainActor (Locator) -> Void = { _ in },
    attach: (() -> Void)? = nil, focusRequest: Int = 0, panelRequest: PanelRequest = PanelRequest(),
    visit: ConversationVisit? = nil,
    lesson: Lesson.ID? = nil, courseLessons: [Lesson] = []
  ) {
    self.init(
      ref: ref, draft: draft, revealPassage: revealPassage, attach: attach, focusRequest: focusRequest,
      panelRequest: panelRequest, visit: visit, lesson: lesson, courseLessons: courseLessons
    ) { EmptyView() }
  }
}

/// Everything said with Loci as a chat, newest at the bottom, with the input field floating over its foot and
/// `tail` after the last message.
///
/// Each row is its own view keyed by its message and part, so a reply that grows while it streams redraws
/// only its last bubble. What was said before the running turn is laid out once, not again as the reply
/// grows. The scroll view is made again once the conversation arrives, so it opens at the latest message
/// measured, not where the lazy stack guessed its rows would end.
struct ConversationView<Tail: View>: View {
  let conversation: Conversation?
  /// Which conversation, for what it runs on before it arrives.
  var ref: ConversationRef?
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
  var panelRequest = PanelRequest()
  var visit: ConversationVisit?
  /// How long the reply being written waits, with no tool after it, before it shows.
  var replyHold = Motion.replyHold
  var courseLessons: [Lesson] = []
  @ViewBuilder var tail: () -> Tail
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns
  /// Starts keeping the newest line in view.
  @State var follow = Following()
  @State private var scrolling = false
  /// The first row in view, kept out of what draws the conversation so scrolling does not draw it again.
  @State private var visibleRow = VisibleRow()
  @State private var localVisit = ConversationVisit()
  @State private var pointedAnswer = PointedAnswer()
  @State private var settled = Remembered(TalkRow.settled)
  /// The running turn's rows, which moving through the conversation leaves as they are.
  @State private var going = Remembered<LiveSoFar, [TalkRow]>(TalkRow.live)
  /// How many of the earliest rows are not drawn; `nil` until the conversation arrives.
  @State private var hidden: Int?
  /// When a reply held back last came due, so the conversation is drawn again to show it.
  @State private var cameDue = Date.distantPast
  @State private var cover = ConversationCover()
  @State private var runtimeIsland = false

  private enum End: Hashable { case latest }

  private var currentVisit: ConversationVisit { visit ?? localVisit }

  var body: some View {
    ScrollViewReader { proxy in
      scroll(using: proxy)
    }
    .id(conversation != nil)
  }

  private func scroll(using proxy: ScrollViewProxy) -> some View {
    let said = said
    let now = standIns?.conversationAt ?? max(cameDue, .now)
    let live = going(LiveSoFar(conversation?.turn, hold: ReplyHold(now: now, wait: replyHold)))
    let reading = currentVisit.reading
    let start = min(hidden ?? RowWindow.opening(in: said, at: reading), said.count)
    let rows = Array(said[start...]) + live
    return ScrollView {
      VStack(alignment: .leading, spacing: Size.messageGap) {
        LazyVStack(alignment: .leading, spacing: Size.messageGap) {
          ForEach(rows) { row in
            view(of: row).arriving()
          }
        }
        .scrollTargetLayout()
        VStack(spacing: 0) {
          tail()
          Color.clear.frame(height: 1).accessibilityHidden(true)
        }
        .id(End.latest)
      }
      .animatingArrivals(said.count(where: \.arrives) + live.count(where: \.arrives))
      .padding(.horizontal, Spacing.m)
      .padding(.top, scale == .main ? Spacing.s : 0)
      .frame(maxWidth: .infinity)
    }
    .defaultScrollAnchor(.top, for: .alignment)
    .defaultScrollAnchor(.bottom, for: .initialOffset)
    .onScrollPhaseChange { _, phase, context in
      if phase == .idle, scrolling { read(at: Following.distanceFromEnd(context.geometry)) }
      scrolling = phase == .tracking || phase == .interacting || phase == .decelerating
    }
    .onScrollGeometryChange(for: CGFloat.self, of: Following.distanceFromEnd) { _, distance in
      if scrolling {
        read(at: distance)
      } else if reading == nil, follow.isOn, distance > 1 {
        scrollToLatest(using: proxy)
      }
    }
    .onScrollTargetVisibilityChange(idType: TalkRow.ID.self, threshold: 0.01) { ids in
      let visible = Set(ids)
      visibleRow.id = rows.first { visible.contains($0.id) }?.id
      if scrolling, !follow.isOn, let first = visibleRow.id { currentVisit.reading = first }
    }
    .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top < 1 }) { _, atTop in
      let said = said
      guard atTop, !follow.isOn, let hidden, hidden > 0, hidden < said.count else { return }
      self.hidden = RowWindow.earlier(than: hidden, in: said)
    }
    .onChange(of: hidden) { earlier, now in
      guard let earlier, let now, now < earlier, earlier < said.count else { return }
      proxy.scrollTo(said[earlier].id, anchor: .top)
    }
    .task(id: ReplyHold.due(conversation?.turn, wait: replyHold)) {
      guard let due = ReplyHold.due(conversation?.turn, wait: replyHold), standIns == nil else { return }
      try? await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
      if !Task.isCancelled { cameDue = .now }
    }
    .onChange(of: conversation != nil, initial: true) { _, loaded in
      guard loaded else { return }
      hidden = start
      if let reading, rows.contains(where: { $0.id == reading }) {
        follow.scrolled(to: .infinity)
        proxy.scrollTo(reading, anchor: .top)
      } else {
        currentVisit.reading = nil
        scrollToLatest(using: proxy)
      }
    }
    .onChange(of: questions) { old, _ in
      guard old != nil else { return }
      scrolling = false
      follow.asked()
      currentVisit.reading = nil
      scrollToLatest(using: proxy)
    }
    .scrollIndicators(.never)
    .blur(radius: panelRequest.making.wrappedValue ? 16 : 0)
    .opacity(panelRequest.making.wrappedValue ? 0.55 : 1)
    .animation(reduceMotion ? nil : Motion.arrive, value: panelRequest.making.wrappedValue)
    .onChange(of: conversation?.turn != nil, initial: true) { _, working in panelRequest.working(working) }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Composer(
        conversation: ref ?? conversation?.ref, busy: conversation?.turn != nil, draft: $draft, send: send, stop: stop,
        startOver: startOver,
        style: scale == .main ? .talk : .companion, attach: scale == .main ? attach : nil, focusRequest: focusRequest,
        making: panelRequest.making, made: panelRequest.made, fill: panelRequest.fill,
        islandOpen: $runtimeIsland
      )
      .transformAnchorPreference(key: RuntimeIslandAnchors.self, value: .bounds) { $0.composer = $1 }
      .overlay(alignment: .top) {
        if follow.offersLatest {
          LatestButton {
            scrolling = false
            follow.returned()
            currentVisit.reading = nil
            scrollToLatest(using: proxy)
          }
          .offset(y: -(LatestButton.size + Spacing.s))
          .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.8)))
        }
      }
      .animation(reduceMotion ? nil : Motion.quick, value: follow.offersLatest)
      .padding(.horizontal, 14)
      .padding(.bottom, scale == .main ? Spacing.s : 14)
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
    .runtimeIsland(open: $runtimeIsland, conversation: ref ?? conversation?.ref)
    .environment(\.conversationCover, cover)
    .background(Palette.canvas)
  }

  private var said: [TalkRow] {
    settled(SaidSoFar(conversation?.entries ?? [], turn: conversation?.turn))
  }

  /// Questions the person has asked; one more means the conversation goes to its end to show the answer.
  private var questions: Int? {
    guard let conversation else { return nil }
    let said = conversation.entries.count {
      if case .message(let message) = $0, case .prompt = message.body { true } else { false }
    }
    return said + (conversation.turn == nil ? 0 : 1)
  }

  private func read(at distance: CGFloat) {
    var next = follow
    next.scrolled(to: distance)
    if next != follow { follow = next }
    if follow.isOn {
      currentVisit.reading = nil
    } else if let first = visibleRow.id {
      currentVisit.reading = first
    }
  }

  private func scrollToLatest(using proxy: ScrollViewProxy) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { proxy.scrollTo(End.latest, anchor: .bottom) }
  }

  @ViewBuilder private func view(of row: TalkRow) -> some View {
    switch row.kind {
    case .day(let day):
      DayDivider(label: Sitting.label(day, now: Date()))
    case .asked(let prompt):
      BubbleRow(speaker: .person, scale: scale) {
        AskedMessage(prompt: prompt, courseLessons: courseLessons, revealPassage: revealPassage)
      }
    case .said(let words, let answer):
      BubbleRow(
        speaker: .loci, scale: scale,
        words: {
          VStack(alignment: .leading, spacing: 0) { ReplyText(text: words, streaming: false, size: scale.fontSize) }
        },
        beside: {
          if let answer, let reply = row.reply { AnswerActions(text: answer, reply: reply, pointed: pointedAnswer) }
        }
      )
      .onHover { [pointedAnswer] in pointedAnswer.hovering($0, over: row.reply) }
    case .doing(let doing):
      DoingLine(doing: doing, size: scale.fontSize)
    case .ended(let ending):
      BubbleRow(speaker: .loci, scale: scale) { EndedTurn(ending: ending) }
    case .startedOver:
      StartedOverLine().padding(.vertical, 10)
    case .saved:
      SavedChip()
    case .savedItems(let items):
      SavedItemsCard(items: items).padding(.vertical, 6)
    case .document(let document):
      DocumentCard(id: row.id, document: document)
    case .links(let links):
      LinkCards(links: links)
    }
  }
}

extension ConversationView where Tail == EmptyView {
  init(
    conversation: Conversation?, draft: Binding<PassageDraft?>, revealPassage: @escaping @MainActor (Locator) -> Void,
    send: @escaping (String, Passage?) async throws(HostError) -> Done, stop: @escaping () async -> Void,
    startOver: (() async throws(HostError) -> Done)? = nil, scale: TalkScale = .main, attach: (() -> Void)? = nil,
    focusRequest: Int = 0, panelRequest: PanelRequest = PanelRequest(), replyHold: Duration = Motion.replyHold,
    follow: Following = Following(), courseLessons: [Lesson] = []
  ) {
    self.init(
      conversation: conversation, draft: draft, revealPassage: revealPassage, send: send, stop: stop,
      startOver: startOver, scale: scale, attach: attach, focusRequest: focusRequest, panelRequest: panelRequest,
      replyHold: replyHold, courseLessons: courseLessons, tail: { EmptyView() }, follow: follow)
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
    }
  }
}
