/// What the interface talks to: commands that do one thing, and subscriptions that keep one view's data
/// current. The same protocol is served in-process and, later, over an encrypted channel, so everything
/// that crosses it is a plain `Codable` value.
public protocol Host: Sendable {
  func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply
  /// The view's data now, then again each time it changes. Dropping the stream ends the subscription.
  func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>>
}

/// One thing the host can be asked to do, with the type of its reply.
public protocol Command: Codable, Sendable {
  associatedtype Reply: Codable, Sendable
  /// Names the command on the wire.
  static var name: String { get }
  func run(on handler: any CommandHandler) async throws(HostError) -> Reply
}

/// The data one view needs, kept current.
public protocol Subscription: Codable, Hashable, Sendable {
  associatedtype Value: Codable, Equatable, Sendable
  /// Names the subscription on the wire.
  static var name: String { get }
  func value(from handler: any CommandHandler) async throws(HostError) -> Value
  /// Whether these changes on disk could change the value.
  func isAffected(by changes: Set<ContentChange>) -> Bool
}

/// What a subscription delivers. A value is sent first and again only when it differs from the last one.
public enum Feed<Value: Codable & Sendable>: Sendable {
  case value(Value)
  /// The data cannot be had right now, such as a mentor that was deleted. A value follows if it comes back.
  case unavailable(HostError)
}

extension Feed: Codable {}
extension Feed: Equatable where Value: Equatable {}

public enum HostError: Error, Hashable, Codable, Sendable {
  /// Nothing by that name or id.
  case notFound(String)
  case alreadyExists(EntityID)
  /// A file that cannot be used; its path and the reason are in the problem.
  case invalidFile(FileProblem)
  /// The request itself cannot be carried out as asked.
  case invalidRequest(String)
  /// Reading or writing failed, with the system's reason.
  case storage(String)
}

/// Why a host could not start. Nothing on disk is changed when this is thrown.
public enum HostStartError: Error, Hashable, Codable, Sendable {
  /// The database is damaged or not a database. Starting with a replaced database loses reading positions.
  case databaseUnreadable(String)
  /// The database was written by a newer Loci.
  case databaseFromNewerVersion(unknownMigrations: [String])
  case storage(String)
}

/// Carries out commands. Each command calls exactly one of these, so a command cannot go unhandled.
public protocol CommandHandler: Sendable {
  func createMentor(_ command: CreateMentor) async throws(HostError) -> Mentor
  func renameMentor(_ command: RenameMentor) async throws(HostError) -> Mentor
  func deleteMentor(_ command: DeleteMentor) async throws(HostError) -> Done
  func listMentors() async throws(HostError) -> [Mentor]
  func mentorPage(_ mentor: EntityID) async throws(HostError) -> MentorPage
  func addTextItem(_ command: AddTextItem) async throws(HostError) -> Item
  func deleteItem(_ command: DeleteItem) async throws(HostError) -> Done
  func listItems() async throws(HostError) -> [Item]
  func itemText(_ item: EntityID) async throws(HostError) -> String
  func itemPage(_ item: EntityID) async throws(HostError) -> ItemPage
  func lessonText(_ lesson: LessonRef) async throws(HostError) -> String
  func lessonCitations(_ lesson: LessonRef) async throws(HostError) -> [Citation]
  func citingLessons(of item: EntityID) async throws(HostError) -> [CitingLesson]
  func search(_ command: Search) async throws(HostError) -> [SearchHit]
  func readingState(of content: ContentRef) async throws(HostError) -> ReadingState?
  func saveReadingPosition(_ command: SaveReadingPosition) async throws(HostError) -> Done
  func markRead(_ content: ContentRef) async throws(HostError) -> Done
  func lessonPage(_ lesson: LessonRef) async throws(HostError) -> LessonPage
  func seeLesson(_ lesson: LessonRef) async throws(HostError) -> String?
  func health() async -> Health
  func sendMessage(_ command: SendMessage) async throws(HostError) -> Done
  func stopTurn(_ command: StopTurn) async throws(HostError) -> Done
  func answerPermission(_ command: AnswerPermission) async throws(HostError) -> Done
  func writeLesson(_ command: WriteLesson) async throws(HostError) -> Done
  func askAboutPassage(_ command: AskAboutPassage) async throws(HostError) -> EntityID
  func conversation(of mentor: EntityID) async throws(HostError) -> Conversation
  func pendingAnswers(on content: ContentRef) async -> [PendingAnswer]
}
