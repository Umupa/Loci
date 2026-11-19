/// How Loci uses the `loci` command: what `loci help` prints, and the skill written for agent programs
/// that read skills. There is one text, so the two never disagree.
public enum ToolGuide {
  public static let text = """
    loci: search and add to the person's library from inside Loci.

    Read items as files (../library/<folder>/). Search and add with loci.
    Run it as "$LOCI"; a plain `loci` on PATH may be another program.

      loci search <words>              full-text search; prints id, title and the matching sentence
      loci show <id>                   kind, title, authors, source, job, and the item's folder
      loci save <url>                  add a web page, paper, video or podcast episode; prints its id at once
      loci import <file> [--title T]   .md: an article you wrote, with you as its author
                                       video or audio file: copied into the library and transcribed
      loci wait <id>                   wait until the item is ready, or say why it is not
      loci help                        this text

    Add --json to print the app's reply as it is.

    - Save or import only what the person asked for, or what you said you would add.
    - After save or import, the item is in the library at once; its text comes when its job is done.
      Run `loci wait <id>` before you read it.
    - Write an article in workspace/ first, then import it. The library keeps its own copy.
    - Exit status 0 means it worked; 1 means it did not, and the message says why; 2 means the
      command was written wrong.
    """

  /// `SKILL.md` for agent programs that look for skills in their working folder.
  public static let skill = """
    ---
    name: loci
    description: Search the person's library and add links, articles you wrote, or media files to it, with the loci command.
    ---

    \(text)
    """
}
