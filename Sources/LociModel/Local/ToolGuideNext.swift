extension ToolGuide {
  /// `loci help next`: cards on the person's deck and approval cards.
  static let next = """
    The deck is a stack of cards at the top of the person's panel column: things that are theirs to deal
    with. Each card is one line of what happened and a question; starting it says the question in the
    conversation it belongs to, as the person. A card lands in the home of the session that puts it: a
    project's session puts it on the project's deck, and the chat's deck shows every project's too.

    - Put a card only for something the person should act on now, not for news. Panels and notes are for
      what they read later.
    - "$LOCI" next add <what happened> --ask <their question> [--key <key>]. The same key (by default the
      words) brings an open card back to the top instead of adding another. A card they declined does not
      come back; the command says so. Both next add and next propose accept --deadline with an ISO-8601
      time and offset, such as 2026-11-27T13:00:00+08:00. Cards from a watch run inherit its deadline and key.
    - "$LOCI" next propose event <title> --at YYYY-MM-DD [HH:mm] [--until HH:mm] [--calendar <name>]
      [--why <line>], or propose reminder <title> [--at YYYY-MM-DD [HH:mm]] [--list <name>]: an approval
      card. Nothing is written until the person approves it, and they can undo it. Only these two exist:
      you cannot pay, order, sign up or send a message, email or post for them, whatever is connected. Asked
      to, say you cannot.
    """
}
