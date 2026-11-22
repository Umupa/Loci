/// What changed, on disk or in what the host keeps in memory. A change says only what to read again,
/// never the new contents, so hearing about the same change twice does no harm.
public enum ContentChange: Hashable, Codable, Sendable {
  /// `item.json` or `content.md`, or the whole folder.
  case item(EntityID)
  case course(EntityID)
  case courseActivity(EntityID)
  case notes(ContentRef)
  /// What the reader has read or seen of this content changed. It lives in the database only.
  case reading(ContentRef)
  /// An item's job moved on: a stage started, progressed, waited, failed or finished. Nothing on disk to
  /// read again until a stage finishes, which also reports `item`.
  case job(EntityID)
  /// Components, speech models or media settings changed; they belong to no item.
  case media
  /// A conversation grew or its turn moved on. Nothing on disk to read again.
  case conversation(ConversationRef)
  /// A turn ended and was stored, so there is more said in all.
  case turnEnded(ConversationRef)
  /// The daily review started or ended.
  case review
  /// Something happened in the library that the main conversation shows.
  case events
  /// A file under `agent/` changed.
  case loci(LociFile)
  /// What Loci runs on changed.
  case runtime
  /// Events were lost or a change could not be placed; read everything again.
  case everything
}

/// The files under `agent/` that the person sees.
public enum LociFile: String, Hashable, Codable, Sendable {
  case soul
  case profile
  case memory
  /// Any day's `notes/<day>.md`.
  case notes
  /// Any day's `diary/<day>.md`.
  case diary
  case avatar
  /// Any panel's `panels/<name>.json`, or which panel is being refreshed.
  case panels
}
