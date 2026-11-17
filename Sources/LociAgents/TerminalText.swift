extension String {
  /// The text without terminal escape sequences, which agents print even when no terminal is attached.
  var plain: String {
    self.replacing(#/\x{1B}\][^\x{07}\x{1B}]*(?:\x{07}|\x{1B}\\)/#, with: "")
      .replacing(#/\x{1B}\[[0-?]*[ -\/]*[@-~]/#, with: "")
  }
}
