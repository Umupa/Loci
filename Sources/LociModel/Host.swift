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
  func modelSettingsAccess() async -> (any ModelSettingsAccess)?
}

/// One thing the host can be asked to do, with the type of its reply.
public protocol Command: Codable, Sendable {
  associatedtype Reply: Codable, Sendable
  /// Names the command on the wire.
  static var name: String { get }
  func run(on handler: any CommandHandler) async throws(HostError) -> Reply
}

/// A command offered to a paired Mac through the remote Host protocol.
public protocol RemoteCommand: Command {}

/// A command offered to agents through the local tool socket.
public protocol LocalToolCommand: Command {}

/// A command only the Mac the companion lives on can run, such as connecting a connector, whose browser
/// must come back to that Mac. Another Mac is told where to do it.
public protocol HostOnlyCommand: Command {}

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
  /// The host is another Mac whose Loci is too old to know the command. Nothing was changed there.
  case olderMac
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
  func setWholeThought(_ command: SetWholeThought) async throws(HostError) -> Note?
  func deleteNote(_ command: DeleteNote) async throws(HostError) -> Done
  func health() async -> Health
  func sendMessage(_ command: SendMessage) async throws(HostError) -> Done
  func stopTurn(_ command: StopTurn) async throws(HostError) -> Done
  func startOver(_ command: StartOver) async throws(HostError) -> Done
  func conversation(_ conversation: ConversationRef) async throws(HostError) -> Conversation
  func companionName() async throws(HostError) -> String
  func renameCompanion(_ command: RenameCompanion) async throws(HostError) -> Done
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
  func probeLink(_ command: ProbeLink) async throws(HostError) -> LinkProbe
  func importChoice() async throws(HostError) -> ImportChoice
  func addLink(_ command: AddLink) async throws(HostError) -> Item
  func importMediaFile(_ command: ImportMediaFile) async throws(HostError) -> Item
  func retryJob(_ item: EntityID) async throws(HostError) -> Job
  func pauseJob(_ item: EntityID) async throws(HostError) -> Done
  func savingBatch() async -> SavingBatch?
  func stopSaving() async throws(HostError) -> Int
  func translateArticle(_ item: EntityID) async throws(HostError) -> Done
  func pickKeyPoints(_ command: PickKeyPoints) async throws(HostError) -> Done
  func keyPointsPage(_ item: EntityID) async throws(HostError) -> KeyPointsPage
  func modelOptions() async throws(HostError) -> ModelOptions
  func jobs() async throws(HostError) -> [Job]
  func job(of item: EntityID) async throws(HostError) -> Job?
  func renameSpeaker(_ command: RenameSpeaker) async throws(HostError) -> Done
  func mediaPage(_ item: EntityID) async throws(HostError) -> MediaPage
  func playback(_ command: ReadPlayback) async throws(HostError) -> Playback
  func mediaFileInfo(of item: EntityID) async throws(HostError) -> MediaFileInfo
  func mediaBytes(_ command: ReadMediaBytes) async throws(HostError) -> Data
  func cover(of item: EntityID) async throws(HostError) -> Data?
  func itemPDF(_ item: EntityID) async throws(HostError) -> Data
  func itemImage(_ command: ReadItemImage) async throws(HostError) -> Data
  func linkPreview(of url: URL) async throws(HostError) -> LinkPreview
  func linkImage(of url: URL) async throws(HostError) -> Data?
  func webPicture(at url: URL) async throws(HostError) -> Data?
  func mediaSetup() async throws(HostError) -> MediaSetup
  func detectComponents(again: Bool) async -> [ComponentStatus]
  func installComponent(_ component: Component) async throws(HostError) -> Done
  func downloadSpeechModel(_ model: SpeechModel) async throws(HostError) -> Done
  func deleteSpeechModel(_ model: SpeechModel) async throws(HostError) -> Done
  func setSpeechModel(_ model: SpeechModel) async throws(HostError) -> MediaSetup
  func readSource(_ url: URL) async throws(HostError) -> String
  func fetchSourceRepository(_ command: FetchSourceRepository) async throws(HostError) -> SourceCheckout
  func clearSourceCache() async throws(HostError) -> Done
  func storage() async throws(HostError) -> StorageReport
  func freeMediaSpace(_ item: EntityID) async throws(HostError) -> Done
  func saveMediaLocally(_ item: EntityID) async throws(HostError) -> Job
  func setBrowserLogin(_ login: BrowserLogin) async throws(HostError) -> MediaSetup
  func handOverBrowserCookies(_ cookies: [BrowserCookie]) async throws(HostError) -> Done
  func panelColumn() async throws(HostError) -> PanelColumn
  func panels() async throws(HostError) -> [PanelEntry]
  func savePanel(_ command: SavePanel) async throws(HostError) -> Done
  func refreshPanel(_ command: RefreshPanel) async throws(HostError) -> Done
  func movePanelToTop(_ command: MovePanelToTop) async throws(HostError) -> Done
  func removePanel(_ command: RemovePanel) async throws(HostError) -> Done
  func editPanel(_ command: EditPanel) async throws(HostError) -> Done
  func markPanelLine(_ command: MarkPanelLine) async throws(HostError) -> Done
  func listCourses() async throws(HostError) -> [CourseEntry]
  func coursePage(_ course: EntityID) async throws(HostError) -> CoursePage
  func readLesson(_ course: EntityID, lesson: Lesson.ID) async throws(HostError) -> String?
  func restoreDeletedCourse() async throws(HostError) -> Course?
  func startCourse(_ command: StartCourse) async throws(HostError) -> Course
  func answerCourseQuestion(_ command: AnswerCourseQuestion) async throws(HostError) -> Done
  func beginCourseSources(_ command: BeginCourseSources) async throws(HostError) -> Done
  func addCourseSource(_ command: AddCourseSource) async throws(HostError) -> CourseSource
  func removeCourseSource(_ command: RemoveCourseSource) async throws(HostError) -> Done
  func beginCourseWriting(_ command: BeginCourseWriting) async throws(HostError) -> Done
  func openLesson(_ command: OpenLesson) async throws(HostError) -> Done
  func writeLessonNow(_ command: WriteLessonNow) async throws(HostError) -> Done
  func deleteCourse(_ command: DeleteCourse) async throws(HostError) -> Done
  func timers() async throws(HostError) -> Timers
  func runs(of schedule: ScheduleRef, limit: Int) async throws(HostError) -> [Run]
  func pauseSchedule(_ command: PauseSchedule) async throws(HostError) -> Done
  func changeSchedule(_ command: ChangeSchedule) async throws(HostError) -> ScheduleEntry
  func removeSchedule(_ command: RemoveSchedule) async throws(HostError) -> Done
  func addSchedule(_ command: AddSchedule) async throws(HostError) -> ScheduleEntry
  func addFollowUp(_ command: AddFollowUp) async throws(HostError) -> FollowUp
  func cancelFollowUp(_ command: CancelFollowUp) async throws(HostError) -> Done
  func recall(_ command: Recall) async throws(HostError) -> [RecallHit]
  func wikiPage(_ name: String) async throws(HostError) -> WikiPage
  func forgetWikiLine(_ command: ForgetWikiLine) async throws(HostError) -> Done
  func connectors() async throws(HostError) -> Connectors
  func connectorCalls(limit: Int) async throws(HostError) -> [ConnectorCall]
  func connect(_ command: Connect) async throws(HostError) -> Authorization
  func addMCPServer(_ command: AddMCPServer) async throws(HostError) -> Authorization
  func cancelConnecting(_ command: CancelConnecting) async throws(HostError) -> Done
  func disconnect(_ command: Disconnect) async throws(HostError) -> Done
  /// `caller` is the session the `loci` command came from, for the record of calls.
  func callConnector(_ command: CallConnector, from caller: ConnectorCall.Caller?) async throws(HostError) -> String
}
