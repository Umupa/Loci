import LociModel

/// What can be done with a highlight from the text: write its thought, ask about it, delete it.
struct NoteActions {
  /// Saves the thought; `nil` removes it.
  var think: (EntityID, String?) -> Void
  /// Hands the highlight to Loci's composer; `nil` where it cannot be asked about.
  var ask: ((EntityID) -> Void)?
  var delete: (EntityID) -> Void

  /// Writing and deleting the highlights on `content` through `host`; nothing is sent while `changesAllowed` is
  /// off, as the Mac behind the window cannot take changes then.
  static func on(
    _ content: ContentRef, host: any LociModel.Host, changesAllowed: Bool, ask: ((EntityID) -> Void)?
  ) -> NoteActions {
    NoteActions(
      think: { note, thought in
        guard changesAllowed else { return }
        Task { _ = try? await host.run(SetNoteThought(content: content, note: note, thought: thought)) }
      },
      ask: ask,
      delete: { note in
        guard changesAllowed else { return }
        Task { _ = try? await host.run(DeleteNote(content: content, note: note)) }
      })
  }
}
