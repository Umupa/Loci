import Foundation
import LociModel
import Testing

@testable import LociUI

@Suite struct LibraryTests {
  let video: Item
  let article: Item
  let podcast: Item

  init() throws {
    var entropy = Sample.Seeded()
    func id(_ offset: Double) -> EntityID {
      EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + offset), entropy: &entropy)
    }
    video = try Item(
      id: id(1), kind: .video(duration: .seconds(2052)), title: "Scheduling at Scale",
      source: URL(string: "https://www.youtube.com/watch?v=O_zcc6XI12g"), site: "CNCF")
    article = try Item(
      id: id(2), kind: .article, title: "Pingora", source: URL(string: "https://blog.cloudflare.com/pingora/"))
    podcast = try Item(id: id(3), kind: .audio(duration: .seconds(4323)), title: "Inference", site: "Latent Space")
  }

  @Test func articlesAndPapersAppearInTheSameCategory() {
    #expect(LibraryCategory(article.kind) == .article)
    #expect(LibraryCategory(.paper) == .article)
  }

  @Test func eachJobStateSaysHowFarAlongOrWhatFixesIt() {
    let item = video.id
    let fraction = Fraction(0.42)
    #expect(
      JobLine(Job(item: item, stage: .download, state: .running(progress: fraction)))
        == .working(.downloading, fraction))
    #expect(JobLine(Job(item: item, stage: .transcribe, state: .running(progress: nil))) == .working(.recognizing, nil))
    #expect(
      JobLine(Job(item: item, stage: .resolve, state: .waiting(.component(.ytDlp))))
        == .action(.downloadComponent(.ytDlp), nil))
    #expect(
      JobLine(Job(item: item, stage: .transcribe, state: .waiting(.speechModel(.largeV3TurboQuantized))))
        == .action(.downloadModel(.largeV3TurboQuantized), nil))
    let outdated = Job.Failure(reason: "Sign in to confirm", remedy: .updateComponent(.ytDlp))
    #expect(
      JobLine(Job(item: item, stage: .resolve, state: .failed(outdated)))
        == .action(.update(.ytDlp), JobLine.Problem(stage: .resolve, cause: nil, reason: "Sign in to confirm")))
    #expect(JobLine(Job(item: item, stage: .resolve, state: .paused(progress: nil))) == .action(.resume, nil))
  }

  @Test func finishedWorkSaysNothing() {
    #expect(JobLine(Job(item: video.id, stage: .outline, state: .done)) == .none)
    #expect(JobLine(nil) == .none)
  }

  @Test func aFailureWithoutARemedyCanBeRetried() {
    let failure = Job.Failure(reason: "Conversion failed!")
    #expect(
      JobLine(Job(item: video.id, stage: .download, state: .failed(failure)))
        == .action(.retry, JobLine.Problem(stage: .download, cause: nil, reason: "Conversion failed!")))
  }

  /// L-S11: a video that is gone offers its original page instead of a retry that cannot help, and says so in
  /// the reader's words rather than yt-dlp's.
  @Test func anUnavailableVideoOffersItsPageAndSaysWhyInPlainWords() {
    let said = "[youtube] O_zcc6XI12g: This video is unavailable"
    let failure = Job.Failure(reason: said, remedy: .openSource, cause: .unavailable)
    let line = JobLine(Job(item: video.id, stage: .resolve, state: .failed(failure)))

    guard case .action(let fix, let problem?) = line else {
      Issue.record("expected a fix")
      return
    }
    #expect(fix == .openSource)
    #expect(problem.reason == said)
    #expect(String(localized: problem.summary) != said)
    #expect(problem.explanation != nil)
  }

  /// L-S11: a failure whose kind is not known is named by the step that failed; the program's words are kept
  /// for the details.
  @Test func anUnknownFailureIsNamedByItsStep() {
    let failure = Job.Failure(reason: "Conversion failed!")
    let line = JobLine(Job(item: video.id, stage: .translate, state: .failed(failure)))

    guard case .action(_, let problem?) = line else {
      Issue.record("expected a fix")
      return
    }
    #expect(problem.summary.key == "job.failedTranslate")
    #expect(problem.explanation == nil)
  }

  @Test func howMuchWasWatchedIsThePositionOverTheLength() throws {
    var progress = Progress()
    progress.states[video.id] = try state(at: 1026, updated: 1)
    #expect(progress.share(of: video) == 0.5)
    progress.states[video.id] = ReadingState(position: nil, finished: true, updatedAt: stamp(2))
    #expect(progress.share(of: video) == 1)
    #expect(progress.share(of: article) == nil)
  }

  @Test func theBylineIsTheLengthAndWhereItComesFrom() {
    #expect(video.byline == "34:12 · CNCF")
    #expect(article.byline == "blog.cloudflare.com")
    #expect(podcast.byline == "1:12:03 · Latent Space")
  }

  @Test func aYouTubeWatchPageOffersToDownloadTheVideo() throws {
    #expect(offer("https://www.youtube.com/watch?v=abc") == .video)
    #expect(offer("https://www.bilibili.com/video/BV1xx411c7mD") == .video)
  }

  @Test func aChannelPageOffersTheVideosOnIt() throws {
    let videos = (1...3).map {
      FoundVideo(url: URL(string: "https://youtube.com/watch?v=\($0)")!, title: "v\($0)", thumbnail: nil, duration: nil)
    }
    #expect(offer("https://www.youtube.com/@cncf/videos", PageFacts(videos: videos)) == .videos(videos))
  }

  /// L-S15: picking a few videos from a long channel starts from none rather than unchecking the rest.
  @Test func theSwitchChecksEveryVideoOrClearsThemAll() throws {
    let videos = (1...3).map {
      FoundVideo(url: URL(string: "https://youtube.com/watch?v=\($0)")!, title: "v\($0)", thumbnail: nil, duration: nil)
    }
    let all = Set(videos.map(\.url))

    #expect(VideoPicker.toggledAll(all, of: videos).isEmpty)
    #expect(VideoPicker.toggledAll([videos[0].url], of: videos) == all)
    #expect(VideoPicker.toggledAll([], of: videos) == all)
  }

  @Test func episodesPapersPDFsAndArticlesOfferToBeAdded() {
    #expect(offer("https://www.xiaoyuzhoufm.com/episode/123") == .add)
    #expect(offer("https://arxiv.org/abs/1706.03762") == .add)
    #expect(offer("https://example.com/download", PageFacts(isPDF: true)) == .add)
    #expect(offer("https://example.com/post", PageFacts(hasArticle: true)) == .add)
  }

  @Test func aPageThatIsNoneOfTheseOffersNothing() {
    #expect(offer("https://example.com/") == nil)
  }

  @Test func aPageAlreadyInTheLibraryOffersToShowIt() {
    #expect(offer("https://youtube.com/watch?v=O_zcc6XI12g&si=share") == .inLibrary(video.id))
    #expect(offer("https://blog.cloudflare.com/pingora#intro", PageFacts(hasArticle: true)) == .inLibrary(article.id))
  }

  private func offer(_ address: String, _ facts: PageFacts = PageFacts()) -> PageOffer? {
    guard let url = URL(string: address) else { return nil }
    return PageOffer(at: url, facts: facts, library: [video, article, podcast])
  }

  private func state(at seconds: Int, updated: Int) throws -> ReadingState {
    ReadingState(
      position: .item(video.id, .time(try TimeSpan(start: .seconds(seconds)))), finished: false,
      updatedAt: stamp(updated))
  }

  private func stamp(_ offset: Int) -> Timestamp {
    Timestamp(millisecondsSince1970: 1_763_337_600_000 + Int64(offset) * 1000)
  }
}
