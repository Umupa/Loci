/// What changed on disk. A change says only what to read again, never the new contents, so hearing
/// about the same change twice does no harm.
public enum ContentChange: Hashable, Codable, Sendable {
  /// `mentor.json`, or the whole folder appeared or went away.
  case mentor(EntityID)
  case catalog(EntityID)
  /// A lesson file was written, changed or removed.
  case lesson(LessonRef)
  /// `item.json` or `content.md`, or the whole folder.
  case item(EntityID)
  case notes(ContentRef)
  /// Events were lost or a change could not be placed; read everything again.
  case everything
}
