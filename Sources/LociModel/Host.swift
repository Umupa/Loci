import Foundation

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
  func notes(on content: ContentRef) async throws(HostError) -> [Note]
  func addNote(_ command: AddNote) async throws(HostError) -> Note
  func setNoteThought(_ command: SetNoteThought) async throws(HostError) -> Note
  func deleteNote(_ command: DeleteNote) async throws(HostError) -> Done
  func health() async -> Health
  func sendMessage(_ command: SendMessage) async throws(HostError) -> Done
  func stopTurn(_ command: StopTurn) async throws(HostError) -> Done
  func startOver(_ command: StartOver) async throws(HostError) -> Done
  func writeLesson(_ command: WriteLesson) async throws(HostError) -> Done
  func conversation(of mentor: EntityID) async throws(HostError) -> Conversation
  func mind(of mentor: EntityID) async throws(HostError) -> Mind
  func detectAgents(again: Bool) async -> [AgentInstallation]
  func agentModels(of provider: Mentor.Provider) async -> [String]
  func agentDefaults() async throws(HostError) -> AgentDefaults
  func setDefaultAgent(_ command: SetDefaultAgent) async throws(HostError) -> AgentDefaults
  func setDefaultModel(_ command: SetDefaultModel) async throws(HostError) -> AgentDefaults
  func lessonLanguage() async throws(HostError) -> LessonLanguage
  func setLessonLanguage(_ command: SetLessonLanguage) async throws(HostError) -> LessonLanguage
  func dataLocation() async -> URL
  func setMentorAgent(_ command: SetMentorAgent) async throws(HostError) -> Mentor
  func addLink(_ command: AddLink) async throws(HostError) -> Item
  func importMediaFile(_ command: ImportMediaFile) async throws(HostError) -> Item
  func retryJob(_ item: EntityID) async throws(HostError) -> Job
  func cancelJob(_ item: EntityID) async throws(HostError) -> Done
  func jobs() async throws(HostError) -> [Job]
  func job(of item: EntityID) async throws(HostError) -> Job?
  func mediaPage(_ item: EntityID) async throws(HostError) -> MediaPage
  func playback(_ command: ReadPlayback) async throws(HostError) -> Playback
  func cover(of item: EntityID) async throws(HostError) -> Data?
  func itemPDF(_ item: EntityID) async throws(HostError) -> Data
  func itemImage(_ command: ReadItemImage) async throws(HostError) -> Data
  func mediaSetup() async throws(HostError) -> MediaSetup
  func detectComponents(again: Bool) async -> [ComponentStatus]
  func installComponent(_ component: Component) async throws(HostError) -> Done
  func downloadSpeechModel(_ model: SpeechModel) async throws(HostError) -> Done
  func deleteSpeechModel(_ model: SpeechModel) async throws(HostError) -> Done
  func setSpeechModel(_ model: SpeechModel) async throws(HostError) -> MediaSetup
  func setBrowserLogin(_ login: BrowserLogin) async throws(HostError) -> MediaSetup
  func handOverBrowserCookies(_ cookies: [BrowserCookie]) async throws(HostError) -> Done
  func askCompanion(_ command: AskCompanion) async throws(HostError) -> Done
  func stopCompanion(_ command: StopCompanion) async throws(HostError) -> Done
  func startOverCompanion(_ command: StartOverCompanion) async throws(HostError) -> Done
  func chooseCompanion(_ command: ChooseCompanion) async throws(HostError) -> ItemConversation
  func itemConversation(on item: EntityID) async throws(HostError) -> ItemConversation
}
