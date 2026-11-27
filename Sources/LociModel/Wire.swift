/// Every command and subscription another Mac may use, and how each travels. A type missing here cannot be
/// used remotely, and the architecture check fails until it is added.
public enum Wire {
  public static let toolCommands: [any LocalToolCommand.Type] = [
    ReadSource.self, FetchSourceRepository.self, AddSchedule.self, AddFollowUp.self, ListConnectors.self,
    CallConnector.self, Recall.self, NameProject.self, DescribeProject.self,
    SaveDataSource.self, TestDataSource.self, ListDataSources.self, PickPanelEntries.self,
    AddNextUp.self, ProposeApproval.self, AddNextUpCondition.self, ListNextUpConditions.self,
    RemoveNextUpCondition.self,
  ]

  /// Commands only the Mac the companion lives on runs; another Mac is refused them.
  public static let hostOnlyCommands: [any HostOnlyCommand.Type] = [
    Connect.self, AddMCPServer.self, CancelConnecting.self,
  ]

  public static let commands: [CommandRoute] = [
    .writes(SendMessage.self), .writes(StopTurn.self), .writes(StartOver.self),
    .reads(ReadConversationRuntime.self), .writes(SetConversationRuntime.self), .reads(DetectAgents.self),
    .reads(AgentModels.self),
    .writes(RenameCompanion.self),
    .writes(SaveSoul.self), .writes(Forget.self), .writes(ForgetWikiLine.self), .writes(SetAvatar.self, lane: .data),
    .writes(ResetAvatar.self),
    .writes(AddTextItem.self), .reads(ProbeLink.self), .reads(ReadImportChoice.self), .writes(AddLink.self),
    .writes(ImportMediaFile.self), .writes(ImportBook.self), .writes(DeleteItems.self),
    .reads(ReadBookContents.self), .reads(ReadBookFile.self, lane: .data),
    .writes(RestoreDeleted.self), .writes(RenameItem.self), .writes(SetCover.self),
    .reads(ListItems.self), .reads(ReadItemText.self), .reads(Search.self),
    .reads(ReadReadingState.self), .writes(SaveReadingPosition.self), .writes(MarkRead.self),
    .writes(AddNote.self), .writes(SetNoteThought.self), .writes(SetWholeThought.self),
    .writes(DeleteNote.self),
    .reads(DataLocation.self),
    .writes(RetryJob.self), .writes(PauseJob.self), .writes(StopSaving.self), .reads(ListJobs.self),
    .writes(TranslateArticle.self), .writes(TidyArticle.self),
    .writes(RenameSpeaker.self), .reads(ReadMediaPage.self), .reads(ReadPlayback.self), .reads(ReadMediaSetup.self),
    .reads(DetectComponents.self), .writes(InstallComponent.self),
    .writes(DownloadSpeechModel.self), .writes(DeleteSpeechModel.self), .writes(SetSpeechModel.self),
    .writes(SetBrowserLogin.self), .writes(HandOverBrowserCookies.self), .writes(FreeMediaSpace.self),
    .writes(SaveMediaLocally.self), .writes(ClearSourceCache.self),
    .reads(ReadCover.self, lane: .data), .reads(ReadItemPDF.self, lane: .data),
    .reads(ReadItemImage.self, lane: .data), .streams(ReadMediaFileInfo.self, lane: .data),
    .reads(ReadLinkPreview.self), .reads(ReadLinkImage.self, lane: .data), .reads(ReadWebPicture.self, lane: .data),
    .streams(ReadMediaBytes.self, lane: .data),
    .writes(PickKeyPoints.self),
    .reads(ListPanels.self), .writes(SavePanel.self), .writes(RefreshPanel.self), .writes(MovePanelToTop.self),
    .writes(RemovePanel.self), .writes(EditPanel.self), .writes(MarkPanelLine.self),
    .writes(StartProject.self), .writes(RenameProject.self), .writes(SetProjectRemembered.self),
    .writes(ArchiveProject.self), .writes(DeleteProject.self), .writes(RestoreDeletedProject.self),
    .writes(SeeProject.self), .writes(PinPanel.self),
    .reads(ListCourses.self), .writes(StartCourse.self), .writes(AnswerCourseQuestion.self),
    .writes(BeginCourseSources.self), .writes(AddCourseSource.self), .writes(RemoveCourseSource.self),
    .writes(BeginCourseWriting.self), .reads(ReadLesson.self), .writes(OpenLesson.self),
    .writes(WriteLessonNow.self), .writes(DeleteCourse.self), .writes(RestoreDeletedCourse.self),
    .reads(ListTimers.self), .writes(PauseSchedule.self), .writes(ChangeSchedule.self),
    .writes(RemoveSchedule.self), .writes(CancelFollowUp.self), .writes(Disconnect.self),
    .reads(ReadUsage.self),
    .writes(StartNextUp.self), .writes(SetNextUp.self), .writes(ApproveNextUp.self), .writes(UndoApproval.self),
  ]

  public static let subscriptions: [any Subscription.Type] = [
    CompanionName.self, OneConversation.self, LociWorking.self, ConversationRuntime.self, LociHome.self, OneDiary.self,
    LociAvatar.self,
    AllItems.self, OneItem.self, ItemCover.self, NotesOn.self, AllJobs.self, ItemJob.self, SavingNow.self,
    ItemMedia.self, WatchCourses.self, WatchCourse.self, WatchLesson.self,
    MediaSettings.self, HealthReport.self, StorageUse.self, ItemKeyPoints.self, WatchPanelColumn.self,
    WatchTimers.self, WatchScheduleRuns.self, WatchWikiPage.self, WatchConnectors.self, WatchConnectorCalls.self,
    AvailableModels.self, WatchProjects.self, WatchSourceHistory.self, WatchNextUps.self,
  ]

  /// The route of a command type, or `nil` when it is not registered.
  public static func route(of command: any Command.Type) -> CommandRoute? {
    commands.first { $0.name == command.name }
  }
}

/// How one command travels between Macs.
public struct CommandRoute: Sendable {
  public let command: any RemoteCommand.Type
  public let effect: Effect
  public let lane: Lane

  public var name: String { command.name }

  public static func reads<C: RemoteCommand>(_ command: C.Type, lane: Lane = .control) -> CommandRoute {
    CommandRoute(command: command, effect: .reads, lane: lane)
  }

  public static func writes<C: RemoteCommand>(_ command: C.Type, lane: Lane = .control) -> CommandRoute {
    CommandRoute(command: command, effect: .writes, lane: lane)
  }

  public static func streams<C: RemoteCommand>(_ command: C.Type, lane: Lane = .control) -> CommandRoute {
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
