import LociMedia
import LociModel
import LociStore

extension JobRun {
  /// Tidies the article a piece at a time and puts the tidied text in place of the original only once every piece
  /// is back. A piece whose tidying does not pass `ArticleTidying`'s checks is asked for once more, then stays as
  /// it was; when no piece passes, the article is left alone and the stage fails. The key points move to their
  /// tidied passages.
  func tidyArticle(_ found: Item) async throws(StageStop) {
    guard found.kind == .article else { return }
    let store = context.store
    guard let text = try stored({ try store.fetchedContent(of: item) }) else {
      throw .failed("The article has no text to tidy.")
    }
    let pieces = ArticleTidying.pieces(of: text)
    let work = try await writer(nil, for: .translation)
    let title = found.title
    let tidy = { @Sendable (_: Int, piece: String) async throws(StageStop) -> String? in
      for _ in 0..<2 {
        let tidied: String
        do throws(HostError) {
          tidied = try await work.agent.tidy(piece, title: title)
        } catch {
          throw .failed(Self.describe(error))
        }
        if ArticleTidying.problem(tidying: piece, into: tidied) == nil { return tidied }
      }
      return nil
    }
    var tidied: [String?] = []
    try await Batches.run(pieces, parallelism: work.parallelism, work: tidy) { piece async throws(StageStop) in
      tidied.append(piece)
      await queue.progress(item, stage: .tidy, Fraction(Double(tidied.count) / Double(pieces.count)))
    }
    if Task.isCancelled { return }
    guard tidied.contains(where: { $0 != nil }) else { throw .failed(Self.untidied) }
    let markdown =
      zip(pieces, tidied).map { original, tidied in
        (tidied ?? original).trimmingCharacters(in: .whitespacesAndNewlines)
      }.filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
    try stored {
      let keyPoints = try store.keyPoints(of: item)
      try store.replaceArticleText(markdown, of: item)
      if let keyPoints { try Self.move(keyPoints, to: markdown, title: title, of: item, in: store) }
    }
  }

  static let untidied = "No piece of the article could be tidied without losing some of it."

  /// The key points on their passages in the tidied text, numbered as it counts them; those whose passage is
  /// gone are let go.
  private static func move(
    _ keyPoints: KeyPoints, to tidied: String, title: String, of item: EntityID, in store: Store
  ) throws {
    let passages = ArticlePassages.of(tidied, title: title)
    let old = keyPoints.points.map { $0.passage?.text ?? "" }
    let found = ArticleTidying.passages(old, in: passages)
    var moved: [KeyPoint] = []
    for (point, passage) in zip(keyPoints.points, found) {
      guard point.passage != nil, let passage, let index = passages.firstIndex(of: passage) else { continue }
      guard (moved.last?.passage?.number ?? 0) < index + 1 else { continue }
      moved.append(
        try KeyPoint(
          place: .passage(try .init(number: index + 1, text: passage)), title: point.title, reason: point.reason))
    }
    if moved.isEmpty {
      try store.removeKeyPoints(of: item)
    } else {
      try store.save(try KeyPoints(points: moved, choice: keyPoints.choice), of: item)
    }
  }
}
