import LociModel

/// Who put an item into the library.
enum Saver: Hashable, Sendable {
  case person
  /// Loci, with the `loci` command, in this conversation; `nil` outside one, such as the daily review.
  case loci(ConversationRef?)
}
