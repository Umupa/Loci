import Foundation

/// What the interface talks to: commands that do one thing, and subscriptions that keep one view's data
/// current. The same protocol is served in-process and over an encrypted channel to another Mac, so
/// everything that crosses it is a plain `Codable` value. Files on this Mac go through `upload` and
/// `localFile`, which never cross.
public protocol Host: Sendable {
  func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply
  /// The view's data now, then again each time it changes. Dropping the stream ends the subscription.
  func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>>
  /// Makes a file on this Mac available to the host's commands; a remote host receives its bytes.
  func upload(_ file: LocalFile) async throws(HostError) -> Upload
  /// `nil` unless the host is this Mac and the place exists.
  func localFile(_ place: LocalPlace) async -> LocalFile?
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
  /// The data cannot be had right now, such as an item that was deleted. A value follows if it comes back.
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
  /// The host is another Mac that cannot be reached now. Nothing was changed, as far as this Mac knows.
  case offline
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
  func addTextItem(_ command: AddTextItem) async throws(HostError) -> Item
  func deleteItems(_ command: DeleteItems) async throws(HostError) -> Done
  func restoreDeleted() async throws(HostError) -> [Item]
  func renameItem(_ command: RenameItem) async throws(HostError) -> Item
  func setCover(_ command: SetCover) async throws(HostError) -> Done
  func listItems() async throws(HostError) -> [Item]
  func itemText(_ item: EntityID) async throws(HostError) -> String
  func itemPage(_ item: EntityID) async throws(HostError) -> ItemPage
  func search(_ command: Search) async throws(HostError) -> [SearchHit]
  func readingState(of content: ContentRef) async throws(HostError) -> ReadingState?
  func saveReadingPosition(_ command: SaveReadingPosition) async throws(HostError) -> Done
  func markRead(_ content: ContentRef) async throws(HostError) -> Done
  func notes(on content: ContentRef) async throws(HostError) -> [Note]
  func addNote(_ command: AddNote) async throws(HostError) -> Note
  func setNoteThought(_ command: SetNoteThought) async throws(HostError) -> Note
  func deleteNote(_ command: DeleteNote) async throws(HostError) -> Done
  func health() async -> Health
  func sendMessage(_ command: SendMessage) async throws(HostError) -> Done
  func stopTurn(_ command: StopTurn) async throws(HostError) -> Done
  func startOver(_ command: StartOver) async throws(HostError) -> Done
  func conversation(_ conversation: ConversationRef) async throws(HostError) -> Conversation
  func lociStatus() async -> LociStatus
  func lociPage() async throws(HostError) -> LociPage
  func diary(of day: Day) async throws(HostError) -> Diary
  func saveSoul(_ command: SaveSoul) async throws(HostError) -> Soul
  func forget(_ command: Forget) async throws(HostError) -> Done
  func avatar() async throws(HostError) -> Avatar?
  func setAvatar(_ command: SetAvatar) async throws(HostError) -> Done
  func resetAvatar() async throws(HostError) -> Done
  func detectAgents(again: Bool) async -> [AgentInstallation]
  func agentModels(of provider: Provider) async -> [String]
  func runtime() async throws(HostError) -> Runtime
  func setRuntime(_ command: SetRuntime) async throws(HostError) -> Runtime
  func dataLocation() async -> HostPath
  func addLink(_ command: AddLink) async throws(HostError) -> Item
  func importMediaFile(_ command: ImportMediaFile) async throws(HostError) -> Item
  func retryJob(_ item: EntityID) async throws(HostError) -> Job
  func cancelJob(_ item: EntityID) async throws(HostError) -> Done
  func translateArticle(_ item: EntityID) async throws(HostError) -> Done
  func jobs() async throws(HostError) -> [Job]
  func job(of item: EntityID) async throws(HostError) -> Job?
  func mediaPage(_ item: EntityID) async throws(HostError) -> MediaPage
  func playback(_ command: ReadPlayback) async throws(HostError) -> Playback
  func mediaFileInfo(of item: EntityID) async throws(HostError) -> MediaFileInfo
  func mediaBytes(_ command: ReadMediaBytes) async throws(HostError) -> Data
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
}
