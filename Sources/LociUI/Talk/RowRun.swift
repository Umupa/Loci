/// Older rows of what was said, drawn together as one item of the conversation's lazy stack.
///
/// The lazy stack walks every item it holds each time a streaming reply grows, so a long conversation laid
/// out row by row costs more with every message. In runs it is a short list. The most recent rows stay one
/// by one: a run whose rows still change, or that takes in rows on screen, leaves the lazy stack unsure where
/// the rows around it are, and it can stop drawing them.
struct RowRun: Identifiable {
  let id: TalkRow.ID
  let rows: ArraySlice<TalkRow>

  static let length = 8
  /// How many of the latest rows of what was said stay one by one.
  static let recent = 64

  /// The older rows in runs, and the recent ones left one by one.
  static func split(_ rows: [TalkRow]) -> (runs: [RowRun], recent: ArraySlice<TalkRow>) {
    let older = max(0, rows.count - recent) / length * length
    let runs = stride(from: 0, to: older, by: length).map { start in
      RowRun(id: rows[start].id, rows: rows[start..<start + length])
    }
    return (runs, rows[older...])
  }
}
