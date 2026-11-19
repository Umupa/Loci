import LociModel
import SwiftUI

/// The pages of the panel beside a video, a podcast or an article.
enum MediaTab: Hashable {
  case transcript, conversation, highlights
}

/// A video or audio item: the player on the left, and beside it the transcript, the conversation with Loci
/// reading along, and the highlights. Space plays and pauses, ← → jump five seconds, < > change speed.
struct MediaScreen: View {
  @Environment(\.host) private var host
  @Environment(\.standIns) private var standIns
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.openPlace) private var openPlace
  @Environment(\.browser) private var browser
  @Environment(\.showFailure) private var showFailure
  let item: Item
  @State private var player: Player
  @State private var media: Feed<MediaPage>?
  @State private var job: Feed<Job?>?
  @State private var notes: Feed<[Note]>?
  @State private var tab = MediaTab.transcript
  @AppStorage(SubtitleMode.key) private var subtitles = SubtitleMode.both
  @AppStorage("subtitlesShown") private var subtitlesShown = true
  @State private var menuOpen = false
  @State private var follow = TranscriptFollow()
  @State private var chosen: ClosedRange<Int>?
  @State private var draft: PassageDraft?
  @State private var panelShown = true
  /// Opened over the stage in a window too narrow to have it beside.
  @State private var panelOver = false
  @State private var width: CGFloat = 0
  @State private var opened = false
  @FocusState private var focused: Bool

  init(item: Item) {
    self.item = item
    _player = State(initialValue: Player(start: .zero, length: item.length))
  }

  var body: some View {
    HStack(spacing: 0) {
      stage
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { menuOpen = false }
      if layout.besideStage {
        panel.frame(width: Size.mediaPanel).transition(.move(edge: .trailing))
      }
    }
    .overlay(alignment: .trailing) {
      if layout.overStage {
        panel.frame(width: Size.mediaPanel)
          .shadow(color: .black.opacity(0.18), radius: 24, x: -6)
          .transition(.move(edge: .trailing))
      }
    }
    .overlay(alignment: .topTrailing) {
      if !layout.besideStage && !layout.overStage {
        PanelButton(title: .loci("panel.expand")) { withAnimation(Motion.fold) { openPanel() } }
          .glassEffect(.regular, in: .capsule)
          .padding(Spacing.s)
      }
    }
    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    .background(Palette.canvas)
    .focusable()
    .focusEffectDisabled()
    .focused($focused)
    .onKeyPress(.space) {
      player.toggle()
      return .handled
    }
    .onKeyPress(.leftArrow) {
      player.skip(by: .seconds(-5))
      return .handled
    }
    .onKeyPress(.rightArrow) {
      player.skip(by: .seconds(5))
      return .handled
    }
    .onKeyPress(characters: CharacterSet(charactersIn: "<,")) { _ in
      player.slower()
      return .handled
    }
    .onKeyPress(characters: CharacterSet(charactersIn: ">.")) { _ in
      player.faster()
      return .handled
    }
    .subscribing(ItemMedia(item: item.id), into: $media)
    .subscribing(ItemJob(item: item.id), into: $job)
    .subscribing(NotesOn(content: .item(item.id)), into: $notes)
    .task(id: item.id) { await open() }
    .task(id: playable) { await load() }
    .onDisappear { player.close() }
  }

  @ViewBuilder private var stage: some View {
    let model = StageModel(
      item: item, player: player, timeline: Timeline(length: length, outline: media?.value?.outline),
      transcript: readable, subtitles: $subtitles, subtitlesShown: $subtitlesShown, menuOpen: $menuOpen)
    if case .audio = item.kind { PodcastStage(model: model) } else { VideoStage(model: model) }
  }

  private var length: Duration {
    player.length ?? item.length ?? media?.value?.transcript?.segments.last?.end ?? .zero
  }

  private var readable: ReadableTranscript? {
    guard let transcript = media?.value?.transcript, !transcript.segments.isEmpty else { return nil }
    return ReadableTranscript(
      transcript: transcript, translations: media?.value?.translations ?? [],
      language: Locale.preferredLanguages.first)
  }

  private var panel: some View {
    VStack(spacing: 0) {
      CompanionHeader(tab: $tab, tabs: tabs) {
        withAnimation(Motion.fold) {
          panelShown = false
          panelOver = false
        }
      }
      Group {
        switch tab {
        case .transcript: transcriptPage
        case .conversation:
          ConversationScreen(ref: .item(item.id), draft: $draft, revealPassage: reveal)
        case .highlights: highlightsPage
        }
      }
      .frame(maxHeight: .infinity)
    }
    .background(Palette.canvas)
    .overlay(alignment: .leading) { Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline) }
  }

  private let tabs: [(value: MediaTab, title: LocalizedStringResource)] = [
    (.transcript, .loci("panel.transcript")), (.conversation, .loci("panel.conversation")),
    (.highlights, .loci("panel.highlights")),
  ]

  @ViewBuilder private var transcriptPage: some View {
    if let readable {
      TranscriptView(
        transcript: readable, chapters: media?.value?.outline?.chapters ?? [], highlights: highlightSpans,
        notes: notes?.value ?? [], mode: subtitlesShown ? subtitles : .both,
        playing: TranscriptFollow.playing(in: readable.segments, at: player.time),
        speakers: speaksInTurns(readable.transcript), growing: recognizing != nil, follow: $follow, chosen: $chosen,
        actions: passageActions(readable), play: { player.seek(to: readable.segments[$0].start) }
      )
      .overlay(alignment: .bottom) {
        if let recognizing { RecognitionCard(progress: recognizing).padding(Spacing.s) }
      }
    } else {
      TranscriptPending(job: job?.value ?? nil) { fix in
        JobFixes(
          host: host, openPlace: openPlace, browser: browser, failed: showFailure, changesAllowed: changesAllowed
        ).apply(fix, to: item)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var highlightsPage: some View {
    let segments = readable?.segments ?? []
    let placed = (notes?.value ?? [])
      .sorted { ($0.locator.time?.start ?? .zero) < ($1.locator.time?.start ?? .zero) }
      .map { note in
        let index = note.locator.time.flatMap { TranscriptFollow.playing(in: segments, at: $0.start) } ?? 0
        return PlacedNote(note: note, range: NSRange(location: index, length: 1))
      }
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: Spacing.xs) {
        ForEach(placed) { note in
          NoteCard(
            content: .item(item.id), placed: note, chosen: nil,
            ask: { ask(note.note.locator, excerpt: note.note.excerpt ?? "") }
          ) {
            if let time = note.note.locator.time { player.seek(to: time.start) }
          }
        }
      }
      .padding(.horizontal, Spacing.s)
      .padding(.bottom, 20)
    }
    .scrollIndicators(.never)
  }

  /// The share of speech recognized so far, while recognition runs.
  private var recognizing: Fraction? {
    guard let job = job?.value ?? nil, job.stage == .transcribe, case .running(let progress) = job.state else {
      return nil
    }
    return progress ?? Fraction(0)
  }

  private var highlightSpans: [ClosedRange<Duration>] {
    (media?.value?.outline?.highlights ?? []).map { $0.span.start...($0.span.end ?? $0.span.start) }
  }

  /// A podcast whose speakers were told apart reads as turns of talk.
  private func speaksInTurns(_ transcript: Transcript) -> Bool {
    guard case .audio = item.kind else { return false }
    return transcript.segments.contains { $0.speaker != nil }
  }

  private func passageActions(_ readable: ReadableTranscript) -> PassageActions {
    PassageActions(
      highlight: { range in
        guard let passage = passage(range, in: readable) else { return nil }
        return try? await host.run(AddNote(locator: passage.locator, excerpt: passage.excerpt)).id
      },
      think: { note, thought in
        Task { _ = try? await host.run(SetNoteThought(content: .item(item.id), note: note, thought: thought)) }
      },
      ask: { range in
        guard let passage = passage(range, in: readable) else { return }
        ask(passage.locator, excerpt: passage.excerpt)
      }, changes: changesAllowed)
  }

  /// The sentences chosen, as a stretch of time and their words.
  private func passage(_ range: NSRange, in readable: ReadableTranscript) -> (locator: Locator, excerpt: String)? {
    let segments = readable.segments
    let last = range.location + max(range.length, 1) - 1
    guard segments.indices.contains(range.location), segments.indices.contains(last),
      let span = try? TimeSpan(start: segments[range.location].start, end: segments[last].end)
    else { return nil }
    let words = segments[range.location...last].map(\.text).joined(separator: " ")
    return (.item(item.id, .time(span)), words)
  }

  private func ask(_ locator: Locator, excerpt: String) {
    draft = PassageDraft(content: .item(item.id), locator: locator, excerpt: excerpt)
    chosen = nil
    withAnimation(Motion.fold) {
      tab = .conversation
      openPanel()
    }
  }

  private var layout: MediaLayout {
    MediaLayout(width: width, panelShown: panelShown, panelOver: panelOver)
  }

  private func openPanel() {
    if MediaLayout(width: width, panelShown: true, panelOver: false).besideStage {
      panelShown = true
    } else {
      panelOver = true
    }
  }

  private func reveal(_ locator: Locator) {
    guard let time = locator.time else { return }
    player.seek(to: time.start)
    follow.resume()
    tab = .transcript
  }

  /// Picks up where the reader left off and wires the player to remember as it goes.
  private func open() async {
    guard !opened else { return }
    opened = true
    let id = item.id
    let host = host
    if let state = try? await host.run(ReadReadingState(content: .item(id))), let time = state.position?.time {
      player.seek(to: time.start)
    }
    player.remember = { time in
      guard let span = try? TimeSpan(start: time) else { return }
      Task { _ = try? await host.run(SaveReadingPosition(content: .item(id), position: .item(id, .time(span)))) }
    }
    player.reachedEnd = { Task { _ = try? await host.run(MarkRead(content: .item(id))) } }
    player.refresh = {
      guard let playback = try? await host.run(ReadPlayback(item: id, refresh: true)) else { return nil }
      return await PlayerSource.of(playback, item: id, on: host)
    }
    if let moment = standIns?.moment { show(moment) } else { focused = true }
  }

  /// Plays once the host can say where from: at once for a downloaded file, after the link is resolved for
  /// a stream.
  private func load() async {
    guard standIns == nil, let playback = try? await host.run(ReadPlayback(item: item.id)),
      let source = await PlayerSource.of(playback, item: item.id, on: host)
    else { return }
    player.load(source)
  }

  /// What may change where the media plays from.
  private var playable: [Bool] {
    [media?.value?.downloaded ?? false, (job?.value ?? nil)?.stage == .download]
  }

  /// Sets the page as a snapshot asks: after the transcript has come to the sentence playing, so scrolling
  /// away leaves it there.
  private func show(_ moment: MediaMoment) {
    if moment.playing { player.showPlaying() }
    chosen = moment.chosen
    menuOpen = moment.subtitleMenuOpen
    if let panel = moment.panel { tab = panel }
    guard moment.scrolledAway else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(600))
      follow.scrolledByHand()
    }
  }
}

/// Where the transcript will be, before there is one.
private struct TranscriptPending: View {
  let job: Job?
  let act: (JobLine.Fix) -> Void

  var body: some View {
    Group {
      if case .none = JobLine(job) {
        Image(systemName: Symbols.recognizing).font(.system(size: 22, weight: .light)).foregroundStyle(Palette.inkFaint)
      } else {
        JobDetail(line: JobLine(job), act: act)
      }
    }
    .padding(Spacing.l)
  }
}

/// Over the foot of the transcript while speech is recognized: how far along.
private struct RecognitionCard: View {
  let progress: Fraction

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(spacing: 7) {
        Image(systemName: Symbols.recognizing).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
        Text(
          joining: Text(.loci("job.recognizing")), Text(verbatim: " \(Int((progress.value * 100).rounded()))%"))
      }
      .font(.system(size: 12, weight: .medium).monospaced())
      .foregroundStyle(Palette.inkMuted)
      GeometryReader { frame in Meter(share: progress.value, width: frame.size.width) }.frame(height: Size.meterHeight)
    }
    .padding(.horizontal, 14)
    .padding(.top, 11)
    .padding(.bottom, 13)
    .background(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.floating)
        .shadow(color: .black.opacity(0.1), radius: 12, y: 8)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(
        Palette.lineStrong, lineWidth: Size.hairline))
  }
}
