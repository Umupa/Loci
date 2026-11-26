/// How much of a long conversation is drawn: its latest rows, and an earlier stretch each time the person
/// reaches the top of what is drawn, kept where it was so the conversation does not jump.
///
/// The conversation's lazy stack measures every row it holds each time a streaming reply grows, so a
/// conversation of thousands of rows drawn whole costs a core while Loci writes. Each stretch starts where a
/// message does, so the top of what is drawn is never half an answer.
enum RowWindow {
  /// About two hundred messages.
  static let length = 600
  /// How many rows reaching the top adds above.
  static let step = 300

  /// Where the drawn rows start when the conversation shows its end.
  static func latest(in rows: [TalkRow]) -> Int {
    start(near: rows.count - length, in: rows)
  }

  static func opening(in rows: [TalkRow], at reading: TalkRow.ID?) -> Int {
    let latest = latest(in: rows)
    guard let reading, let index = rows.firstIndex(where: { $0.id == reading }), index < latest else { return latest }
    return earlier(than: index, in: rows)
  }

  /// Where the drawn rows start once the stretch before `start` is added.
  static func earlier(than start: Int, in rows: [TalkRow]) -> Int {
    Self.start(near: min(start, rows.count) - step, in: rows)
  }

  private static func start(near index: Int, in rows: [TalkRow]) -> Int {
    guard index > 0 else { return 0 }
    return rows[..<index].lastIndex(where: \.arrives) ?? 0
  }
}
