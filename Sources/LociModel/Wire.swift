/// Every command and subscription another Mac may use, and how each travels. A type missing here cannot be
/// used remotely, and the architecture check fails until it is added.
public enum Wire {
  public static let commands: [CommandRoute] = [
    .writes(CreateMentor.self), .writes(RenameMentor.self), .writes(DeleteMentor.self), .reads(ListMentors.self),
    .writes(SetMentorAgent.self), .reads(ReadCatalog.self),
    .writes(AddTextItem.self), .writes(AddLink.self), .writes(ImportMediaFile.self), .writes(DeleteItem.self),
    .reads(ListItems.self), .reads(ReadItemText.self), .reads(ItemCitations.self),
    .reads(ReadLessonText.self), .reads(LessonCitations.self), .writes(SeeLesson.self), .writes(WriteLesson.self),
    .reads(Search.self),
    .reads(ReadReadingState.self), .writes(SaveReadingPosition.self), .writes(MarkRead.self),
    .writes(AddNote.self), .writes(SetNoteThought.self), .writes(DeleteNote.self),
    .writes(SendMessage.self), .writes(StopTurn.self), .writes(StartOver.self),
    .writes(AskCompanion.self), .writes(StopCompanion.self), .writes(ChooseCompanion.self),
    .writes(StartOverCompanion.self),
    .reads(DetectAgents.self), .reads(AgentModels.self), .reads(ReadAgentDefaults.self),
    .writes(SetDefaultAgent.self), .writes(SetDefaultModel.self),
    .reads(ReadLessonLanguage.self), .writes(SetLessonLanguage.self), .reads(DataLocation.self),
    .writes(RetryJob.self), .writes(CancelJob.self), .reads(ListJobs.self),
    .reads(ReadMediaPage.self), .reads(ReadPlayback.self), .reads(ReadMediaSetup.self),
    .reads(DetectComponents.self), .writes(InstallComponent.self),
    .writes(DownloadSpeechModel.self), .writes(DeleteSpeechModel.self), .writes(SetSpeechModel.self),
    .writes(SetBrowserLogin.self), .writes(HandOverBrowserCookies.self),
    .reads(ReadCover.self, lane: .data), .reads(ReadItemPDF.self, lane: .data),
    .reads(ReadItemImage.self, lane: .data), .streams(ReadMediaFileInfo.self, lane: .data),
    .streams(ReadMediaBytes.self, lane: .data),
  ]

  public static let subscriptions: [any Subscription.Type] = [
    AllMentors.self, OneMentor.self, MentorMind.self, MentorConversation.self, OneLesson.self, AllItems.self,
    OneItem.self, NotesOn.self, CompanionConversation.self, AllJobs.self, ItemJob.self, ItemMedia.self,
    MediaSettings.self, HealthReport.self,
  ]

  /// The route of a command type, or `nil` when it is not registered.
  public static func route(of command: any Command.Type) -> CommandRoute? {
    commands.first { $0.name == command.name }
  }
}

/// How one command travels between Macs.
public struct CommandRoute: Sendable {
  public let command: any Command.Type
  public let effect: Effect
  public let lane: Lane

  public var name: String { command.name }

  public static func reads<C: Command>(_ command: C.Type, lane: Lane = .control) -> CommandRoute {
    CommandRoute(command: command, effect: .reads, lane: lane)
  }

  public static func writes<C: Command>(_ command: C.Type, lane: Lane = .control) -> CommandRoute {
    CommandRoute(command: command, effect: .writes, lane: lane)
  }

  public static func streams<C: Command>(_ command: C.Type, lane: Lane = .control) -> CommandRoute {
    CommandRoute(command: command, effect: .streams, lane: lane)
  }

  public enum Effect: Sendable {
    /// The reply is kept, for reading while the Mac is offline.
    case reads
    /// Fails with `HostError.offline` while the Mac is offline.
    case writes
    /// A read whose reply is not worth keeping, such as a range of a video.
    case streams
  }
}

/// The control connection carries commands, subscriptions and their changes. The data connection carries
/// bytes: PDFs, covers, images, media ranges, uploads. A large download never holds up a conversation.
public enum Lane: String, Hashable, Codable, Sendable { case control, data }
