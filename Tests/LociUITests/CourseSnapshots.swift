import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// The courses page, the builder through its stages and the reading page, in light and dark, each moving part
/// caught at a fixed moment.
@MainActor
@Suite(.serialized, .onStage)
struct CourseSnapshots {
  /// The design's window without the sidebar.
  static let page = CGSize(width: 1048, height: 880)
  /// A wider window, with room for the conversation beside a lesson.
  static let wide = CGSize(width: 1360, height: 880)

  static func shoot(
    _ name: String, _ view: some View, appearance: Snapshot.Appearance, english: Bool = false, size: CGSize = page,
    standIns: StandIns = StandIns()
  ) async throws {
    let file = try await Snapshot.render(
      view.environment(\.standIns, standIns).background(Palette.canvas)
        .lociHost(FakeHost(try Sample(problems: false), courses: try SampleCourses())),
      named: name, size: size,
      appearance: appearance, locale: Locale(identifier: english ? "en" : "zh-Hans"), settle: .milliseconds(700))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  /// Draws `view` with SwiftUI's own renderer, which keeps 3D turns and shadows that the window's picture
  /// flattens: for the moving parts caught half way. It cannot draw AppKit fields or glass.
  static func shootDirectly(
    _ name: String, _ view: some View, appearance: Snapshot.Appearance, english: Bool = false, size: CGSize
  ) throws {
    let content = view.frame(width: size.width, height: size.height)
      .background(Palette.canvas)
      .environment(\.standIns, StandIns())
      .environment(\.locale, Locale(identifier: english ? "en" : "zh-Hans"))
      .environment(\.colorScheme, appearance == .dark ? .dark : .light)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    var picture: CGImage?
    NSAppearance(named: appearance.name)?.performAsCurrentDrawingAppearance { picture = renderer.cgImage }
    let png = try #require(
      picture.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) })
    let directory = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "output/snapshots")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: directory.appending(path: "\(name)-\(appearance.rawValue).png"))
    #expect(png.count > 10_000)
  }

  /// CO-S1: a book lifting and opening a little under the pointer, beside one at rest.
  @Test(arguments: Snapshot.Appearance.allCases)
  func bookUnderPointer(appearance: Snapshot.Appearance) throws {
    try Self.shootDirectly(
      "course-book-hover", BookPair(), appearance: appearance, size: CGSize(width: 620, height: 440))
  }

  /// CO-S1, CO-S2: the gallery with books read to different lengths, one never opened, one being built, and the
  /// pointer on one.
  @Test(arguments: Snapshot.Appearance.allCases)
  func gallery(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-gallery", ShelfStage(books: CourseSamples.books, pointed: CourseSamples.books[1].id),
      appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func galleryInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-gallery-en", ShelfStage(books: CourseSamples.englishBooks, wish: ""), appearance: appearance,
      english: true)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func emptyGallery(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("course-gallery-empty", ShelfStage(books: [], wish: "Raft"), appearance: appearance)
  }

  /// CO-S2: the builder part way out of the field.
  @Test(arguments: Snapshot.Appearance.allCases)
  func builderGrowing(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-builder-open", PageStage(shown: try BuilderSamples.asking(), said: 1, growth: 0.5), appearance: appearance
    )
  }

  /// CO-S3: the first question, its answers, and the title page with only the title on it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func goalQuestion(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-goal-question", PageStage(shown: try BuilderSamples.asking(), said: 1), appearance: appearance)
  }

  /// CO-S3: the chosen answer half way to its line.
  @Test(arguments: Snapshot.Appearance.allCases)
  func goalFlying(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-goal-flying",
      PageStage(
        shown: try BuilderSamples.asking(), said: 1,
        moment: BuilderMoment(flight: (answer: 0, line: 0, progress: 0.5))),
      appearance: appearance)
  }

  /// CO-S3: answers that can hold at once, the line before them half inked.
  @Test(arguments: Snapshot.Appearance.allCases)
  func goalToggles(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-goal-toggles",
      PageStage(shown: try BuilderSamples.ticking(), said: 6, moment: BuilderMoment(ink: (line: 1, progress: 0.5))),
      appearance: appearance)
  }

  /// CO-S4: Loci's account and the two replies.
  @Test(arguments: Snapshot.Appearance.allCases)
  func goalConfirm(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-goal-confirm", PageStage(shown: try BuilderSamples.confirming(), said: 6), appearance: appearance)
  }

  /// CO-S4: subtitle and length written, the seal down, the next step inviting.
  @Test(arguments: Snapshot.Appearance.allCases)
  func goalSealed(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-goal-sealed",
      PageStage(shown: try BuilderSamples.sealed(), said: 6, moment: BuilderMoment(invitation: 0.5)),
      appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases, [false, true])
  func actionEchoes(appearance: Snapshot.Appearance, english: Bool) async throws {
    let at = Timestamp(millisecondsSince1970: 1_763_340_000_000)
    let prompts = try CourseActionSamples.prompts()
    let entries = prompts.map { Conversation.Entry.message(Message(id: EntityID(), at: at, body: .prompt($0))) }
    let conversation = Conversation(ref: .course(BuilderSamples.raft), entries: entries, turn: nil)
    let view = ConversationView(
      conversation: conversation, draft: .constant(nil), revealPassage: { _ in }, send: { _, _ in Done() }, stop: {},
      scale: .companion)
    try await Self.shoot(
      english ? "course-action-echoes-en" : "course-action-echoes", view,
      appearance: appearance, english: english, size: CGSize(width: 500, height: 760))
  }

  /// CO-S5: sources landing and being read, one under the pointer, the builder's edge alight, Loci at work.
  @Test(arguments: Snapshot.Appearance.allCases)
  func sources(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-sources",
      PageStage(
        shown: try BuilderSamples.gathering(), said: 6, thinking: true,
        moment: BuilderMoment(
          landing: (id: BuilderSamples.sourceIDs[5], progress: 0.45), pointedSource: BuilderSamples.sourceIDs[3])),
      appearance: appearance)
  }

  /// CO-S6: the open book, contents beaded, the second lesson being written.
  @Test(arguments: Snapshot.Appearance.allCases)
  func writing(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-writing", PageStage(shown: try BuilderSamples.writing(), said: 6), appearance: appearance)
  }

  /// CO-S6: the first lesson's page part way over.
  @Test(arguments: Snapshot.Appearance.allCases)
  func pageTurning(appearance: Snapshot.Appearance) throws {
    try Self.shootDirectly(
      "course-writing-turn",
      OpenBook(
        title: "Raft", subtitle: "一群机器怎么对一串日志达成一致", lessons: BuilderSamples.lessons(written: 1, writing: true),
        leaf: BuilderSamples.leaves[1], turning: (leaf: BuilderSamples.leaves[0], progress: 0.32)
      ).padding(60), appearance: appearance, size: CGSize(width: 720, height: 560))
  }

  /// CO-S6: a lesson longer than its page: the pages stay level, the latest paragraphs at the foot and the earlier
  /// ones fading out under the title.
  @Test(arguments: Snapshot.Appearance.allCases)
  func writingPastThePage(appearance: Snapshot.Appearance) throws {
    try Self.shootDirectly(
      "course-writing-long",
      OpenBook(
        title: "Raft", subtitle: "一群机器怎么对一串日志达成一致", lessons: BuilderSamples.lessons(written: 2, writing: true),
        leaf: BuilderSamples.longLeaf
      ).padding(60), appearance: appearance, size: CGSize(width: 720, height: 560))
  }

  /// CO-S7: the builder part way back into its book.
  @Test(arguments: Snapshot.Appearance.allCases)
  func builderCollapsing(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-builder-collapse",
      PageStage(shown: try BuilderSamples.writing(), said: 6, growth: 0.35, origin: .book(BuilderSamples.raft)),
      appearance: appearance)
  }

  /// CO-S8: reading the first lesson a third of the way down, a highlight on it, a source under the pointer, Loci
  /// beside it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func reading(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-reader", ReadingStage(shown: ReadingSamples.first(), pointedSource: BuilderSamples.sourceIDs[3]),
      appearance: appearance, size: Self.wide, standIns: StandIns(readThrough: 0.32))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func readingInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-reader-en", ReadingStage(shown: ReadingSamples.first(), panel: false), appearance: appearance,
      english: true, standIns: StandIns(readThrough: 0.32))
  }

  /// The narrowest window: the contents and Loci folded out of the lesson's way, each a button in a corner.
  @Test(arguments: Snapshot.Appearance.allCases)
  func readingNarrow(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-reader-narrow", ReadingStage(shown: ReadingSamples.first()), appearance: appearance,
      size: CGSize(width: Size.windowMinimum.width - Size.sidebarIdeal, height: 700),
      standIns: StandIns(readThrough: 0.32))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func readingUnwrittenNarrow(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-reader-unwritten-narrow", ReadingStage(shown: ReadingSamples.unwritten()), appearance: appearance,
      size: CGSize(width: Size.windowMinimum.width - Size.sidebarIdeal, height: 700))
  }

  /// The whole window at its narrowest, reading the course as the host serves it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func readingInANarrowWindow(appearance: Snapshot.Appearance) async throws {
    try await Self.window(
      "course-window-reader-narrow", at: .courses(BuilderSamples.raft), appearance: appearance,
      size: CGSize(width: Size.windowMinimum.width, height: 700))
  }

  /// CO-S9: at the end of the lesson, the next one being written.
  @Test(arguments: Snapshot.Appearance.allCases)
  func readingNextWriting(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-reader-next-writing", ReadingStage(shown: ReadingSamples.first(nextWriting: true), panel: false),
      appearance: appearance, standIns: StandIns(readThrough: 1, endInView: true))
  }

  /// CO-S10: a lesson not written yet.
  @Test(arguments: Snapshot.Appearance.allCases)
  func readingUnwritten(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "course-reader-unwritten", ReadingStage(shown: ReadingSamples.unwritten()), appearance: appearance)
  }

  /// CO-S1: Courses in the sidebar between papers and the browser, the gallery served by the host.
  @Test(arguments: Snapshot.Appearance.allCases)
  func inTheWindow(appearance: Snapshot.Appearance) async throws {
    try await Self.window("course-window", at: .courses(nil), appearance: appearance)
  }

  /// CO-S8, CO-S9: reading the course as the host serves it: the second lesson open, as the first is read, its
  /// text not written in the sample so the pencil lines show; then the first, with its highlight.
  @Test(arguments: Snapshot.Appearance.allCases)
  func readingInTheWindow(appearance: Snapshot.Appearance) async throws {
    try await Self.window("course-window-reader", at: .courses(BuilderSamples.raft), appearance: appearance)
  }

  static func window(
    _ name: String, at place: Place, appearance: Snapshot.Appearance, size: CGSize = LibrarySnapshots.window
  ) async throws {
    let view = MachineWindow(memory: WindowMemory(recall: { WindowState(place: place) }, remember: { _ in }))
      .lociHost(FakeHost(try Sample(problems: false), courses: try SampleCourses()))
      .environment(\.standIns, StandIns())
      .defaultAppStorage(LibrarySnapshots.defaults(panel: false))
    let file = try await Snapshot.render(
      view, named: name, size: size, appearance: appearance, settle: .milliseconds(1500))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  /// Every family of drawing on each cloth, to see what titles turn into.
  @Test(arguments: Snapshot.Appearance.allCases)
  func motifs(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("course-motifs", MotifSheet(), appearance: appearance, size: CGSize(width: 1048, height: 700))
  }
}

/// The shelf on its own.
private struct ShelfStage: View {
  let books: [CourseBook]
  var pointed: EntityID?
  @State var wish = ""

  var body: some View {
    CourseShelf(books: books, wish: $wish, pointed: pointed, start: { _ in }, open: { _ in }, delete: { _ in })
  }
}

/// The page with the Raft course's builder open over the shelf, and what was said about it.
private struct PageStage: View {
  let shown: BuilderShown
  /// How many of the sample's lines have been said.
  let said: Int
  var thinking = false
  var moment = BuilderMoment()
  var growth: Double?
  var origin = GrowthOrigin.wish
  @State var wish = ""
  @State private var draft: PassageDraft?

  var body: some View {
    var books = CourseSamples.books
    books[0] = CourseBook(
      id: BuilderSamples.raft, title: "Raft", subtitle: "",
      building: .init(stage: shown.stage, fraction: shown.stage == .writing ? shown.fraction : nil))
    return CoursesLayout(
      books: books, building: BuilderSamples.raft,
      builder: { _ in
        CourseBuilder(shown: shown, actions: BuilderActions(), moment: moment) {
          ConversationView(
            conversation: CourseConversation.of(Array(BuilderSamples.said.prefix(said)), thinking: thinking),
            draft: $draft, revealPassage: { _ in }, send: { _, _ in Done() }, stop: {}, scale: .companion
          ) {
            if let question = shown.question { QuestionTail(question: question) }
          }
        }
      }, origin: origin, growth: growth, wish: $wish, start: { _ in }, open: { _ in }, delete: { _ in })
  }
}

/// The reading page with a sample conversation beside it.
private struct ReadingStage: View {
  let shown: ReadingShown
  var pointedSource: EntityID?
  var panel = true
  @State private var draft: PassageDraft?

  var body: some View {
    CourseReader(shown: shown, actions: ReadingActions(), pointedSource: pointedSource) {
      ConversationView(
        conversation: CourseConversation.sample, draft: $draft, revealPassage: { _ in }, send: { _, _ in Done() },
        stop: {}, scale: .companion)
    }
    .defaultAppStorage(LibrarySnapshots.defaults(panel: panel))
  }
}

private struct BookPair: View {
  var body: some View {
    HStack(alignment: .top, spacing: 40) {
      GalleryBook(book: CourseSamples.books[1], pointed: false, hidden: false) {}
      GalleryBook(book: CourseSamples.books[3], pointed: true, hidden: false) {}
      GalleryBook(book: CourseSamples.books[0], pointed: false, hidden: false) {}
    }
    .frame(width: 540)
    .padding(40)
  }
}

private struct MotifSheet: View {
  var body: some View {
    let titles = CourseSamples.motifTitles
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 18), count: 6), spacing: 18) {
      ForEach(titles, id: \.self) { title in
        VStack(spacing: 6) {
          ClothBook(title: title, subtitle: "", read: 0)
          Text(verbatim: title).font(.system(size: 10)).lineLimit(1)
        }
      }
    }
    .padding(24)
  }
}

enum CourseSamples {
  static let books: [CourseBook] = [
    CourseBook(
      id: EntityID(), title: "Raft", subtitle: "一群机器怎么对一串日志达成一致",
      building: .init(stage: .writing, fraction: 0.3)),
    CourseBook(id: EntityID(), title: "Kubernetes 调度器", subtitle: "一个 Pod 怎么找到它的机器", read: 0.5),
    CourseBook(id: EntityID(), title: "CubeSandbox 的隔离", subtitle: "一台宿主机上跑一万个不信任的程序", read: 0.2),
    CourseBook(id: EntityID(), title: "LSM 树与存储引擎", subtitle: "把随机写变成顺序写的代价", read: 0.9),
    CourseBook(id: EntityID(), title: "TCP 拥塞控制", subtitle: "不知道网络多宽时怎么发"),
  ]

  static let englishBooks: [CourseBook] = [
    CourseBook(
      id: EntityID(), title: "Raft", subtitle: "How machines agree on one log",
      building: .init(stage: .sources, fraction: 0.6)),
    CourseBook(id: EntityID(), title: "The Kubernetes Scheduler", subtitle: "How a pod finds its machine", read: 0.4),
    CourseBook(id: EntityID(), title: "Sandbox Isolation", subtitle: "Ten thousand untrusted programs on one host"),
    CourseBook(id: EntityID(), title: "LSM Trees", subtitle: "The price of turning random writes sequential", read: 1),
  ]

  static let motifTitles = [
    "Raft", "Kubernetes 调度器", "CubeSandbox 的隔离", "LSM 树与存储引擎", "TCP 拥塞控制", "Paxos", "向量数据库", "eBPF",
    "Go 的调度器", "Rust 所有权", "Transformer", "MVCC", "B+ 树", "CRDT", "一致性哈希", "QUIC", "零拷贝", "布隆过滤器",
  ]
}
