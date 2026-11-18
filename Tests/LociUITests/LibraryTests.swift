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

  @Test func eachJobStateSaysHowFarAlongOrWhatFixesIt() {
    let item = video.id
    let fraction = Fraction(0.42)
    #expect(
      JobLine(Job(item: item, stage: .download, state: .running(progress: fraction)))
        == .working(.downloading, fraction))
    #expect(JobLine(Job(item: item, stage: .transcribe, state: .running(progress: nil))) == .working(.recognizing, nil))
    #expect(
      JobLine(Job(item: item, stage: .resolve, state: .waiting(.component(.ytDlp))))
        == .action(.downloadComponent(.ytDlp), reason: nil))
    #expect(
      JobLine(Job(item: item, stage: .transcribe, state: .waiting(.speechModel(.largeV3TurboQuantized))))
        == .action(.downloadModel(.largeV3TurboQuantized), reason: nil))
    let outdated = Job.Failure(reason: "Sign in to confirm", remedy: .updateComponent(.ytDlp))
    #expect(
      JobLine(Job(item: item, stage: .resolve, state: .failed(outdated)))
        == .action(.update(.ytDlp), reason: "Sign in to confirm"))
    #expect(JobLine(Job(item: item, stage: .resolve, state: .stopped)) == .action(.resume, reason: nil))
  }

  @Test func finishedWorkSaysNothing() {
    #expect(JobLine(Job(item: video.id, stage: .outline, state: .done)) == .none)
    #expect(JobLine(nil) == .none)
  }

  @Test func aFailureWithoutARemedyCanBeRetried() {
    let failure = Job.Failure(reason: "Video unavailable")
    #expect(
      JobLine(Job(item: video.id, stage: .resolve, state: .failed(failure)))
        == .action(.retry, reason: "Video unavailable"))
  }

  @Test func theShelfHoldsWhatIsStartedAndUnfinishedLatestFirst() throws {
    var progress = Progress()
    progress.states[video.id] = try state(at: 600, updated: 10)
    progress.states[podcast.id] = try state(at: 60, updated: 20)
    progress.states[article.id] = ReadingState(position: nil, finished: true, updatedAt: stamp(30))
    #expect(progress.shelf(of: [video, article, podcast]).map(\.id) == [podcast.id, video.id])
  }

  @Test func theShelfHoldsAtMostThree() throws {
    var progress = Progress()
    var items: [Item] = []
    var entropy = Sample.Seeded()
    for index in 0..<5 {
      let item = try Item(
        id: EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + Double(index)), entropy: &entropy),
        kind: .video(duration: .seconds(100)), title: "v\(index)")
      items.append(item)
      progress.states[item.id] = ReadingState(
        position: .item(item.id, .time(try TimeSpan(start: .seconds(1)))), finished: false, updatedAt: stamp(index))
    }
    #expect(progress.shelf(of: items).count == 3)
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
