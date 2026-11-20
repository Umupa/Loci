import LociModel
import SwiftUI

/// The pages of the panel beside a video or a podcast.
enum MediaTab: Hashable {
  case transcript, keyPoints, conversation, highlights
}

/// A video or audio item: the player on the left, and beside it the transcript, the key points, the
/// conversation with Loci reading along, and the highlights; or how subtitles look, while that is open. Space plays and pauses, ← → jump five seconds, < > change speed.
struct MediaScreen: View {
  @Environment(\.host) private var host
  @Environment(\.standIns) private var standIns
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.openPlace) private var openPlace
  @Environment(\.browser) private var browser
  @Environment(\.showFailure) private var showFailure
  @Environment(\.machineChoice) private var machineChoice
  @Environment(\.deletions) private var deletions
  @Environment(\.undoManager) private var undoManager
  let item: Item
  let initialTime: Duration?
  @State private var player: Player
  @State private var media: Feed<MediaPage>?
  @State private var job: Feed<Job?>?
  @State private var notes: Feed<[Note]>?
  @State private var keyPoints: Feed<KeyPointsPage>?
  @State private var tab = MediaTab.transcript
  @AppStorage(SubtitleMode.key) private var subtitles = SubtitleMode.both
  @AppStorage(SubtitleStyle.key) private var style = SubtitleStyle.standard
  @State private var styling = false
  @State private var onlyKeyPoints = false
  @State private var frames = KeyPointFrames()
  @AppStorage("subtitlesShown") private var subtitlesShown = true
  @State private var menuOpen = false
  @State private var follow = TranscriptFollow()
  @State private var chosen: ClosedRange<Int>?
  @State private var draft: PassageDraft?
  @AppStorage(PanelMemory.key) private var panelShown = PanelMemory.shownAtFirst
  /// Opened over the stage in a window too narrow to have it beside.
  @State private var panelOver = false
  @State private var width: CGFloat = 0
  @State private var opened = false
  @State private var followedPassage = false
  @FocusState private var focused: Bool

  init(item: Item, initialTime: Duration? = nil) {
    self.item = item
    self.initialTime = initialTime
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
    .subscribing(ItemKeyPoints(item: item.id), into: $keyPoints)
    .task(id: item.id) { await open() }
    .task(id: playable) { await load() }
    .task(id: [points.compactMap(\.span?.start), [player.soundOnly ? .zero : .seconds(1)]]) { await drawFrames() }
    .onChange(of: playback) { player.only = onlyKeyPoints ? playback : nil }
    .onChange(of: onlyKeyPoints) { _, only in
      player.only = only ? playback : nil
      if only, case .jump(let start) = playback.step(at: player.time) { player.seek(to: start) }
    }
    .onDisappear { player.close() }
  }

  @ViewBuilder private var stage: some View {
    let model = StageModel(
      item: item, player: player,
      timeline: Timeline(length: length, outline: media?.value?.outline, keyPoints: points), transcript: readable,
      subtitles: $subtitles, subtitlesShown: $subtitlesShown, menuOpen: $menuOpen, style: $style,
      onlyKeyPoints: points.isEmpty ? nil : $onlyKeyPoints, styling: styling,
      openStyle: { withAnimation(Motion.fold) { styleSubtitles() } })
    if let preparing = PreparingStage.job(job?.value ?? nil, playable: player.canPlay) {
      PreparingStage(
        item: item, job: preparing,
        actions: .on(host, fixes: fixes, failed: showFailure, deletions: deletions, undoManager: undoManager))
    } else if onlyThere {
      OnlyThereStage(item: item)
    } else {
      VStack(spacing: 0) {
        if player.availability == .failed {
          Text(.loci("player.failed")).font(Typography.bodyEmphasis).padding(.top, Spacing.m)
        }
        if case .audio = item.kind {
          if subtitlesShown, let readable {
            PodcastLyrics(model: model, transcript: readable).transition(.opacity)
          } else {
            PodcastStage(model: model).transition(.opacity)
          }
        } else {
          VideoStage(model: model)
        }
      }
    }
  }

  /// O-S4: another Mac's item that is not saved there plays only on that Mac.
  private var onlyThere: Bool {
    machineChoice?.link != nil && media?.value?.downloaded == false
  }

  private var fixes: JobFixes {
    JobFixes(host: host, openPlace: openPlace, browser: browser, failed: showFailure, changesAllowed: changesAllowed)
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
      if styling {
        SubtitleStylePanel(style: $style, mode: $subtitles) {
          withAnimation(Motion.fold) { styling = false }
        }
      } else {
        CompanionHeader(tab: $tab, tabs: tabs) {
          withAnimation(Motion.fold) {
            panelShown = false
            panelOver = false
          }
        }
        Group {
          switch tab {
          case .transcript: transcriptPage
          case .keyPoints:
            KeyPointsPanel(
              item: item.id, media: item, page: keyPoints?.value, current: currentKeyPoint, frames: frames,
              open: { if let span = $0.span { play(from: span.start) } })
          case .conversation:
            ConversationScreen(ref: .item(item.id), draft: $draft, revealPassage: reveal)
          case .highlights:
            MediaNotesPage(
              item: item.id, notes: notes?.value ?? [], segments: readable?.segments ?? [], play: player.seek,
              ask: { ask($0.locator, excerpt: $0.excerpt ?? "") })
          }
        }
        .frame(maxHeight: .infinity)
      }
    }
    .background(Palette.canvas)
    .overlay(alignment: .leading) { Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline) }
  }

  private let tabs: [(value: MediaTab, title: LocalizedStringResource)] = [
    (.transcript, .loci("panel.transcript")), (.keyPoints, .loci("panel.keyPoints")),
    (.conversation, .loci("panel.conversation")), (.highlights, .loci("panel.highlights")),
  ]

  private var points: [KeyPoint] { keyPoints?.value?.keyPoints?.points ?? [] }

  private var playback: KeyPointPlayback { KeyPointPlayback(points) }

  /// The key point playing and how far through it.
  private var currentKeyPoint: (index: Int, progress: Double?)? {
    guard let index = playback.playing(at: player.time) else { return nil }
    let span = playback.spans[index]
    let length = Double((span.upperBound - span.lowerBound).roundedMilliseconds)
    return (index, Double((player.time - span.lowerBound).roundedMilliseconds) / max(length, 1))
  }

  private func play(from start: Duration) {
    player.seek(to: start)
    player.play()
    follow.resume()
  }

  private func styleSubtitles() {
    styling.toggle()
    if styling { openPanel() }
  }

  private func drawFrames() async {
    guard case .video = item.kind, !player.soundOnly, let asset = player.engine.currentItem?.asset else { return }
    await frames.draw(points.compactMap(\.span?.start), from: asset)
  }

  @ViewBuilder private var transcriptPage: some View {
    if let readable {
      TranscriptView(
        transcript: readable, chapters: media?.value?.outline?.chapters ?? [], keyPoints: playback.spans,
        notes: notes?.value ?? [], mode: subtitlesShown ? subtitles : .both, order: style.order,
        playing: TranscriptFollow.playing(in: readable.segments, at: player.time),
        speakers: speaksInTurns(readable.transcript), growing: recognizing != nil, follow: $follow, chosen: $chosen,
        actions: passageActions(readable), play: { player.seek(to: readable.segments[$0].start) }
      )
      .overlay(alignment: .bottom) {
        if let recognizing { RecognitionCard(progress: recognizing).padding(Spacing.s) }
      }
    } else {
      TranscriptPending(job: job?.value ?? nil, act: act)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func act(_ fix: JobLine.Fix) {
    fixes.apply(fix, to: item)
  }

  /// The share of speech recognized so far, while recognition runs.
  private var recognizing: Fraction? {
    guard let job = job?.value ?? nil, job.stage == .transcribe, case .running(let progress, _) = job.state else {
      return nil
    }
    return progress ?? Fraction(0)
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
    followedPassage = true
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
    if let initialTime {
      player.seek(to: initialTime)
    } else if let state = try? await host.run(ReadReadingState(content: .item(id))),
      !followedPassage, let time = state.position?.time
    {
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
    guard standIns == nil, !onlyThere, let playback = try? await host.run(ReadPlayback(item: item.id)),
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
    onlyKeyPoints = moment.onlyKeyPoints
    if moment.panelFolded { panelShown = false }
    styling = moment.styling
    if let panel = moment.panel { tab = panel }
    guard moment.scrolledAway else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(600))
      follow.scrolledByHand()
    }
  }
}
