/// What changed, on disk or in what the host keeps in memory. A change says only what to read again,
/// never the new contents, so hearing about the same change twice does no harm.
public enum ContentChange: Hashable, Codable, Sendable {
  /// `mentor.json`, or the whole folder appeared or went away.
  case mentor(EntityID)
  /// `catalog.yaml` or `glossary.yaml`.
  case catalog(EntityID)
  /// A lesson file was written, changed or removed.
  case lesson(LessonRef)
  /// `item.json` or `content.md`, or the whole folder.
  case item(EntityID)
  case notes(ContentRef)
  /// A mentor's conversation grew or its turn moved on. Nothing on disk to read again.
  case conversation(EntityID)
  /// Answers to questions about this content arrived, finished or failed. Nothing on disk to read again.
  case answers(ContentRef)
  /// What the reader has read or seen of this content changed. It lives in the database only.
  case reading(ContentRef)
  /// Events were lost or a change could not be placed; read everything again.
  case everything
}
