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
  /// A file under `agent/` changed.
  case loci(LociFile)
  /// A project was started, changed, archived, deleted or brought back, or something new happened in one.
  case projects
  /// What a conversation runs on, or what new conversations of a kind start on, changed.
  case runtime
  /// A schedule or follow-up, the inbox, or a run changed. They live in the database only.
  case timers
  /// A connector, a connection under way, or the record of calls changed. They live in the database and
  /// the keychain.
  case connectors
  /// A source got records or failed to; its snapshot and history live in the database.
  case source(SourceKey)
  /// A next-up card or a reminder condition changed. They live in the database only.
  case nextUps
  /// Events were lost or a change could not be placed; read everything again.
  case everything
}

/// The files under `agent/` that the person sees.
public enum LociFile: String, Hashable, Codable, Sendable {
  case name
  case soul
  case profile
  case memory
  /// Any day's `notes/<day>.md`.
  case notes
  /// Any day's `diary/<day>.md`.
  case diary
  case avatar
  /// `feelings.json`.
  case feelings
  /// Any panel's `panels/<name>.json`, or which panel is being refreshed.
  case panels
  /// Any page of the wiki, `memory/<page>.md`.
  case wiki
}
